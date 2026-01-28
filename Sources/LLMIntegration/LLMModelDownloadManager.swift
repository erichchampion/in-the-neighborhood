import Foundation
import Combine

/// Manages background download of LLM models
/// Singleton class that handles downloading GGUF models from HuggingFace
public final class LLMModelDownloadManager: NSObject, ObservableObject, @unchecked Sendable {
    // MARK: - Singleton

    public static let shared = LLMModelDownloadManager()

    // MARK: - Published State

    @Published public var downloadState: DownloadState = .notStarted
    @Published public var downloadProgress: Double = 0.0

    // MARK: - Download State

    public enum DownloadState: String, Codable, Sendable {
        case notStarted
        case downloading
        case completed
        case failed
    }

    // MARK: - Properties

    private var downloadTask: URLSessionDownloadTask?
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.in-the-neighborhood.llm-download")
        config.isDiscretionary = false  // Download even on cellular
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    public private(set) var currentModelConfig: LLMModelConfiguration?
    private let stateKey = "llmDownloadState"
    private let progressKey = "llmDownloadProgress"
    private let currentModelKey = "currentDownloadingModelID"
    /// UserDefaults key for selected model ID (must match SettingsManager.selectedModelIDKey)
    private let selectedModelIDKey = "selectedModelID"

    // MARK: - Initialization

    private override init() {
        super.init()

        // Load persisted state
        loadState()

        // Validate restored state
        // If state is "downloading" but no model exists and no active download task,
        // this is a stale state from a previous session - reset it
        if downloadState == .downloading && !isModelAvailable() {
            LoggingService.shared.info(
                "Clearing stale 'downloading' state from previous session",
                category: "LLMDownload"
            )
            downloadState = .notStarted
            downloadProgress = 0.0
            saveState()
        }

        // If model exists, mark as completed
        if isModelAvailable() {
            downloadState = .completed
            downloadProgress = 1.0
        }

        LoggingService.shared.info(
            "LLMModelDownloadManager initialized - state: \(downloadState.rawValue)",
            category: "LLMDownload"
        )
    }

    // MARK: - Public API

    /// Get path to model file for a specific model (checks bundle first, then Application Support)
    /// - Parameter modelID: Model identifier to check
    /// - Returns: URL to model file, or nil if not found
    public func getModelPath(for modelID: LLMModelID) -> URL? {
        // Check bundle first (highest priority)
        // Only return bundled model if it's the default model, since the bundle can only contain one model
        // The bundle model uses "llm.gguf" for backward compatibility
        if modelID == LLMModelCatalog.defaultModelID,
           let bundlePath = BundleHelper.path(forResource: "llm", ofType: "gguf") {
            return URL(fileURLWithPath: bundlePath)
        }

        // Check Application Support directory
        guard let modelConfig = LLMModelCatalog.shared.model(for: modelID) else {
            return nil
        }

        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            LoggingService.shared.error(
                "Could not access Application Support directory",
                category: "LLMDownload"
            )
            return nil
        }

        let modelPath = appSupportURL.appendingPathComponent(modelConfig.localFileName)

        if FileManager.default.fileExists(atPath: modelPath.path) {
            return modelPath
        }

        return nil
    }

    /// Returns the user's selected model ID from UserDefaults, or the default model if unset
    public func selectedModelID() -> LLMModelID {
        guard let rawValue = UserDefaults.standard.string(forKey: selectedModelIDKey),
              let modelID = LLMModelID(rawValue: rawValue) else {
            return LLMModelCatalog.defaultModelID
        }
        return modelID
    }
    
    /// Get path to model file (checks bundle first, then Application Support)
    /// Uses the user's selected model ID
    /// - Returns: URL to model file, or nil if not found
    public func getModelPath() -> URL? {
        return getModelPath(for: selectedModelID())
    }

    /// Check if a specific model is available (bundled or downloaded)
    /// - Parameter modelID: Model identifier to check
    /// - Returns: True if model file exists
    public func isModelAvailable(for modelID: LLMModelID) -> Bool {
        return getModelPath(for: modelID) != nil
    }

    /// Check if model is available (bundled or downloaded)
    /// Uses the user's selected model ID
    /// - Returns: True if model file exists
    public func isModelAvailable() -> Bool {
        return isModelAvailable(for: selectedModelID())
    }

    /// Delete model file for a specific model
    /// - Parameter modelID: Model identifier to delete
    /// - Throws: Error if deletion fails
    func deleteModel(for modelID: LLMModelID) throws {
        guard let modelPath = getModelPath(for: modelID) else {
            LoggingService.shared.info(
                "Model file not found for \(modelID.rawValue), nothing to delete",
                category: "LLMDownload"
            )
            return
        }

        // Don't delete bundled models
        if BundleHelper.path(forResource: "llm", ofType: "gguf") != nil {
            LoggingService.shared.info(
                "Model is bundled, skipping deletion",
                category: "LLMDownload"
            )
            return
        }

        try FileManager.default.removeItem(at: modelPath)

        LoggingService.shared.info(
            "Model deleted: \(modelPath.path)",
            category: "LLMDownload"
        )

        // Reset state if this was the current model
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.currentModelConfig?.id == modelID {
                self.downloadState = .notStarted
                self.downloadProgress = 0.0
                self.currentModelConfig = nil
                self.saveState()
            }
        }
    }

    /// Start download for a specific model if not available
    /// - Parameter modelID: Model identifier to download
    /// - Throws: LLMServiceError if download fails to start
    public func startDownload(for modelID: LLMModelID) async throws {
        guard let modelConfig = LLMModelCatalog.shared.model(for: modelID) else {
            throw LLMServiceError.modelNotFound
        }

        // Check if model already exists
        if isModelAvailable(for: modelID) {
            LoggingService.shared.info(
                "Model already available at: \(getModelPath(for: modelID)?.path ?? "unknown")",
                category: "LLMDownload"
            )
            await MainActor.run {
                downloadState = .completed
                downloadProgress = 1.0
                currentModelConfig = modelConfig
                saveState()
            }
            return
        }

        // Check if download already in progress - do this FIRST to avoid cancelling active downloads
        guard downloadState != .downloading else {
            LoggingService.shared.info(
                "Download already in progress (\(Int(downloadProgress * 100))%)",
                category: "LLMDownload"
            )
            return
        }

        // Cancel any existing stale download task before starting a new one
        // This ensures only one download is active at a time
        if downloadTask != nil {
            LoggingService.shared.info(
                "Cancelling existing download task before starting new download",
                category: "LLMDownload"
            )
            downloadTask?.cancel()
            downloadTask = nil
        }

        // Start download
        await MainActor.run {
            downloadState = .downloading
            downloadProgress = 0.0
            currentModelConfig = modelConfig
            saveState()
        }

        let downloadURL = modelConfig.downloadURL

        LoggingService.shared.info(
            "Starting download of \(modelConfig.id.displayName) from \(downloadURL.absoluteString)",
            category: "LLMDownload"
        )

        let request = URLRequest(url: downloadURL)
        downloadTask = urlSession.downloadTask(with: request)
        downloadTask?.resume()
    }

    /// Start download if selected model not available
    /// - Throws: LLMServiceError if download fails to start
    public func startDownloadIfNeeded() async throws {
        try await startDownload(for: selectedModelID())
    }

    /// Cancel ongoing download
    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil

        // Update state synchronously on main thread if we're already on it,
        // otherwise dispatch async. This ensures immediate state update for UI.
        if Thread.isMainThread {
            self.downloadState = .notStarted
            self.downloadProgress = 0.0
            self.currentModelConfig = nil
            self.saveState()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.downloadState = .notStarted
                self?.downloadProgress = 0.0
                self?.currentModelConfig = nil
                self?.saveState()
            }
        }

        LoggingService.shared.info(
            "Download cancelled",
            category: "LLMDownload"
        )
    }

    // MARK: - State Persistence

    private func saveState() {
        UserDefaults.standard.set(downloadState.rawValue, forKey: stateKey)
        UserDefaults.standard.set(downloadProgress, forKey: progressKey)
        if let modelID = currentModelConfig?.id {
            UserDefaults.standard.set(modelID.rawValue, forKey: currentModelKey)
        }
    }

    private func loadState() {
        if let stateString = UserDefaults.standard.string(forKey: stateKey),
           let state = DownloadState(rawValue: stateString) {
            downloadState = state
        }

        let progress = UserDefaults.standard.double(forKey: progressKey)
        if progress > 0 {
            downloadProgress = progress
        }

        // Load current model if available
        if let modelIDString = UserDefaults.standard.string(forKey: currentModelKey),
           let modelID = LLMModelID(rawValue: modelIDString) {
            currentModelConfig = LLMModelCatalog.shared.model(for: modelID)
        }
    }

    // MARK: - File Operations

    private func moveDownloadedFile(from tempLocation: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default

        // Create Application Support directory if needed
        let parentDir = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Remove existing file if present
        if fileManager.fileExists(atPath: destinationURL.path) {
            LoggingService.shared.info(
                "Removing existing model file at \(destinationURL.path)",
                category: "LLMDownload"
            )
            try fileManager.removeItem(at: destinationURL)
        }

        // Move downloaded file
        try fileManager.moveItem(at: tempLocation, to: destinationURL)

        LoggingService.shared.info(
            "Model file moved to \(destinationURL.path)",
            category: "LLMDownload"
        )
    }

    private func validateDownloadedFile(at url: URL, for modelID: LLMModelID) throws {
        let fileManager = FileManager.default

        // Get file size
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? Int64 else {
            throw NSError(
                domain: "LLMModelDownload",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not determine file size"]
            )
        }

        LoggingService.shared.info(
            "Downloaded file size: \(fileSize) bytes (\(fileSize / 1_000_000)MB)",
            category: "LLMDownload"
        )

        // Validate file size
        let isValid = LLMModelCatalog.shared.validateFileSize(fileSize, for: modelID)
        guard isValid else {
            guard let modelConfig = LLMModelCatalog.shared.model(for: modelID) else {
                throw NSError(
                    domain: "LLMModelDownload",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Model configuration not found"]
                )
            }
            let expectedGB = Double(modelConfig.expectedFileSize) / 1_000_000_000.0
            let actualGB = Double(fileSize) / 1_000_000_000.0
            throw NSError(
                domain: "LLMModelDownload",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Downloaded file size (\(String(format: "%.2f", actualGB))GB) does not match expected size (\(String(format: "%.2f", expectedGB))GB)"
                ]
            )
        }

        LoggingService.shared.info(
            "File size validation passed",
            category: "LLMDownload"
        )
    }
}

// MARK: - URLSessionDownloadDelegate

extension LLMModelDownloadManager: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        LoggingService.shared.info(
            "Download finished, file at temporary location: \(location.path)",
            category: "LLMDownload"
        )

        // Ignore completion callbacks from cancelled/old tasks
        // Check that this callback is for the current active download task
        guard let currentTask = self.downloadTask,
              currentTask === downloadTask else {
            LoggingService.shared.info(
                "Ignoring completion callback from cancelled/old download task",
                category: "LLMDownload"
            )
            try? FileManager.default.removeItem(at: location)
            return
        }

        // Get destination URL in Application Support
        guard let modelConfig = currentModelConfig else {
            LoggingService.shared.error(
                "No model configuration available for downloaded file",
                category: "LLMDownload"
            )
            DispatchQueue.main.async { [weak self] in
                self?.downloadState = .failed
                self?.saveState()
            }
            try? FileManager.default.removeItem(at: location)
            return
        }

        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            LoggingService.shared.error(
                "Could not access Application Support directory for downloaded file",
                category: "LLMDownload"
            )
            DispatchQueue.main.async { [weak self] in
                self?.downloadState = .failed
                self?.saveState()
            }
            try? FileManager.default.removeItem(at: location)
            return
        }

        let destinationURL = appSupportURL.appendingPathComponent(modelConfig.localFileName)

        do {
            // Validate downloaded file
            try validateDownloadedFile(at: location, for: modelConfig.id)

            // Move to Application Support
            try moveDownloadedFile(from: location, to: destinationURL)

            // Update state on main thread
            DispatchQueue.main.async { [weak self] in
                self?.downloadState = .completed
                self?.downloadProgress = 1.0
                self?.saveState()

                LoggingService.shared.info(
                    "Download completed successfully",
                    category: "LLMDownload"
                )
            }
        } catch {
            LoggingService.shared.error(
                "Download failed during file processing: \(error.localizedDescription)",
                category: "LLMDownload"
            )

            DispatchQueue.main.async { [weak self] in
                self?.downloadState = .failed
                self?.saveState()
            }

            // Clean up temporary file
            try? FileManager.default.removeItem(at: location)
        }
    }

    public func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Ignore progress updates from cancelled/old tasks
            // Check that this callback is for the current active download task
            guard let currentTask = self.downloadTask,
                  currentTask === downloadTask else {
                return
            }
            // Don't update progress if download was cancelled (state is .notStarted)
            // This prevents race conditions where progress updates arrive after cancellation
            guard self.downloadState == .downloading else {
                return
            }
            // Verify this callback is for the current model
            guard self.currentModelConfig != nil else {
                return
            }
            self.downloadProgress = progress
            self.saveState()
        }

        // Log progress every 10%
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let currentTask = self.downloadTask,
                  currentTask === downloadTask,
                  self.downloadState == .downloading else {
                return
            }
            if Int(progress * 10) > Int((self.downloadProgress - 0.1) * 10) {
                LoggingService.shared.info(
                    "Download progress: \(Int(progress * 100))% (\(totalBytesWritten / 1_000_000)MB / \(totalBytesExpectedToWrite / 1_000_000)MB)",
                    category: "LLMDownload"
                )
            }
        }
    }

    public func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        // Ignore completion callbacks from cancelled/old tasks
        // Check that this callback is for the current active download task
        guard let currentTask = self.downloadTask,
              currentTask === task else {
            if let error = error {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    LoggingService.shared.info(
                        "Ignoring cancellation callback from old download task",
                        category: "LLMDownload"
                    )
                } else {
                    LoggingService.shared.info(
                        "Ignoring error callback from old download task: \(error.localizedDescription)",
                        category: "LLMDownload"
                    )
                }
            }
            return
        }

        if let error = error {
            // Don't mark as failed if download was explicitly cancelled
            // Cancelled downloads should maintain the .notStarted state set by cancelDownload()
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                LoggingService.shared.info(
                    "Download cancelled by user",
                    category: "LLMDownload"
                )
                // Don't change state - cancelDownload() already set it to .notStarted
                return
            }

            LoggingService.shared.error(
                "Download failed with error: \(error.localizedDescription)",
                category: "LLMDownload"
            )

            DispatchQueue.main.async { [weak self] in
                self?.downloadState = .failed
                self?.saveState()
            }
        }
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        LoggingService.shared.info(
            "Background URL session finished all events",
            category: "LLMDownload"
        )
    }
}
