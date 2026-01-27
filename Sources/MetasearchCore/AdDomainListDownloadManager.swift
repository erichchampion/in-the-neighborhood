import Foundation
import Combine

/// Manages download and parsing of ad domain blacklists
/// Singleton class that handles downloading hosts files from publicly maintained sources
public final class AdDomainListDownloadManager: NSObject, ObservableObject, @unchecked Sendable {
    // MARK: - Singleton
    
    public static let shared = AdDomainListDownloadManager()
    
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
    
    private var downloadTask: URLSessionDataTask?
    private let session: URLSession
    private let hostsFileURL = URL(string: "https://raw.githubusercontent.com/stevenblack/hosts/master/hosts")!
    private let hostsFileName = "ad-domains-hosts.txt"
    private let parsedDomainsFileName = "ad-domains-parsed.json"
    
    private let stateKey = "adDomainListDownloadState"
    private let progressKey = "adDomainListDownloadProgress"
    
    // MARK: - Initialization
    
    private override init() {
        self.session = URLSession.shared
        super.init()
        
        // Load persisted state
        loadState()
        
        // Validate restored state
        // If state is "downloading" but no list exists, this is a stale state - reset it
        if downloadState == .downloading && !isListAvailable() {
            print("[AdDomainListDownloadManager] Clearing stale 'downloading' state from previous session")
            downloadState = .notStarted
            downloadProgress = 0.0
            saveState()
        }
        
        // If list exists, mark as completed
        if isListAvailable() {
            downloadState = .completed
            downloadProgress = 1.0
        }
        
        print("[AdDomainListDownloadManager] Initialized - state: \(downloadState.rawValue)")
    }
    
    // MARK: - Public API
    
    /// Check if parsed ad domain list is available
    /// - Returns: True if parsed domains file exists
    public func isListAvailable() -> Bool {
        return getParsedDomainsPath() != nil && FileManager.default.fileExists(atPath: getParsedDomainsPath()!.path)
    }
    
    /// Get path to parsed ad domains file
    /// - Returns: URL to parsed domains file, or nil if not found
    public func getParsedDomainsPath() -> URL? {
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            print("[AdDomainListDownloadManager] Could not access Application Support directory")
            return nil
        }
        
        return appSupportURL.appendingPathComponent(parsedDomainsFileName)
    }
    
    /// Get cached ad domains
    /// - Returns: Set of ad domains, or nil if not available
    public func getAdDomains() -> Set<String>? {
        guard let parsedPath = getParsedDomainsPath(),
              FileManager.default.fileExists(atPath: parsedPath.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: parsedPath)
            let domains = try JSONDecoder().decode([String].self, from: data)
            return Set(domains)
        } catch {
            print("[AdDomainListDownloadManager] Failed to load parsed domains: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Start download if list not available
    /// - Throws: Error if download fails to start
    public func startDownloadIfNeeded() async throws {
        // Check if list already exists
        if isListAvailable() {
            print("[AdDomainListDownloadManager] Ad domain list already available")
            await MainActor.run {
                downloadState = .completed
                downloadProgress = 1.0
                saveState()
            }
            return
        }
        
        // Check if download already in progress
        guard downloadState != .downloading else {
            print("[AdDomainListDownloadManager] Download already in progress (\(Int(downloadProgress * 100))%)")
            return
        }
        
        // Cancel any existing download task
        downloadTask?.cancel()
        downloadTask = nil
        
        // Start download
        await MainActor.run {
            downloadState = .downloading
            downloadProgress = 0.0
            saveState()
        }
        
        print("[AdDomainListDownloadManager] Starting download from \(hostsFileURL.absoluteString)")
        
        do {
            let (data, response) = try await session.data(from: hostsFileURL)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw NSError(
                    domain: "AdDomainListDownload",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]
                )
            }
            
            guard let hostsContent = String(data: data, encoding: .utf8) else {
                throw NSError(
                    domain: "AdDomainListDownload",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to decode hosts file as UTF-8"]
                )
            }
            
            print("[AdDomainListDownloadManager] Download completed, size: \(data.count) bytes")
            
            // Update progress
            await MainActor.run {
                downloadProgress = 0.5
                saveState()
            }
            
            // Save raw hosts file
            try saveHostsFile(hostsContent)
            
            // Parse and save parsed domains
            let domains = parseHostsFile(hostsContent)
            print("[AdDomainListDownloadManager] Parsed \(domains.count) ad domains")
            
            try saveParsedDomains(domains)
            
            // Update state
            await MainActor.run {
                downloadState = .completed
                downloadProgress = 1.0
                saveState()
            }
            
            print("[AdDomainListDownloadManager] Download and parsing completed successfully")
        } catch {
            print("[AdDomainListDownloadManager] Download failed: \(error.localizedDescription)")
            
            await MainActor.run {
                downloadState = .failed
                saveState()
            }
            
            throw error
        }
    }
    
    // MARK: - File Operations
    
    private func saveHostsFile(_ content: String) throws {
        guard let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw NSError(
                domain: "AdDomainListDownload",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not access Application Support directory"]
            )
        }
        
        let hostsFilePath = appSupportURL.appendingPathComponent(hostsFileName)
        
        // Create directory if needed
        try FileManager.default.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true
        )
        
        // Write hosts file
        try content.write(to: hostsFilePath, atomically: true, encoding: .utf8)
        
        print("[AdDomainListDownloadManager] Saved hosts file to \(hostsFilePath.path)")
    }
    
    private func saveParsedDomains(_ domains: Set<String>) throws {
        guard let parsedPath = getParsedDomainsPath() else {
            throw NSError(
                domain: "AdDomainListDownload",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not get path for parsed domains"]
            )
        }
        
        // Convert Set to Array for JSON encoding
        let domainsArray = Array(domains).sorted()
        let data = try JSONEncoder().encode(domainsArray)
        
        try data.write(to: parsedPath, options: .atomic)
        
        print("[AdDomainListDownloadManager] Saved \(domains.count) parsed domains to \(parsedPath.path)")
    }
    
    // MARK: - Hosts File Parsing
    
    /// Parse standard hosts file format and extract domain names
    /// - Parameter content: Hosts file content as string
    /// - Returns: Set of domain names (normalized to lowercase)
    private func parseHostsFile(_ content: String) -> Set<String> {
        var domains = Set<String>()
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            // Skip empty lines
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            
            // Skip comment lines
            if trimmed.hasPrefix("#") {
                continue
            }
            
            // Parse line: IP domain1 domain2 ...
            // Format: 0.0.0.0 domain.com or 127.0.0.1 domain.com
            let components = trimmed.split(whereSeparator: { $0.isWhitespace })
            guard components.count >= 2 else {
                continue
            }
            
            // Check if first component is an IP address (0.0.0.0 or 127.0.0.1)
            let ipComponent = String(components[0])
            guard ipComponent == "0.0.0.0" || ipComponent == "127.0.0.1" else {
                continue
            }
            
            // Extract domains from remaining components
            for i in 1..<components.count {
                var domain = String(components[i])
                
                // Remove inline comments
                if let commentIndex = domain.firstIndex(of: "#") {
                    domain = String(domain[..<commentIndex])
                }
                
                domain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Skip localhost entries
                if domain.lowercased() == "localhost" || domain.isEmpty {
                    continue
                }
                
                // Normalize domain (lowercase)
                let normalizedDomain = domain.lowercased()
                
                // Basic validation: domain should contain at least one dot
                if normalizedDomain.contains(".") && !normalizedDomain.hasPrefix(".") && !normalizedDomain.hasSuffix(".") {
                    domains.insert(normalizedDomain)
                }
            }
        }
        
        return domains
    }
    
    // MARK: - State Persistence
    
    private func saveState() {
        UserDefaults.standard.set(downloadState.rawValue, forKey: stateKey)
        UserDefaults.standard.set(downloadProgress, forKey: progressKey)
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
    }
}
