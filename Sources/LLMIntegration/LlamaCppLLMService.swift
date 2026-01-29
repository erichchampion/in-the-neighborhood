import Foundation
import MetasearchCore
import llama

/// llama.cpp-based LLM service implementation for on-device query enhancement
/// Falls back to rule-based parsing when model is not available
/// Thread-safe via serial DispatchQueue (llama.cpp is not thread-safe)
public actor LlamaCppLLMService: LLMService {
    // MARK: - Properties
    
    // These properties are accessed from the serial DispatchQueue
    // They are safe because all llama.cpp operations are serialized
    nonisolated(unsafe) private var llamaContext: OpaquePointer?
    nonisolated(unsafe) private var llamaModel: OpaquePointer?
    nonisolated(unsafe) private var backendInitialized = false
    nonisolated(unsafe) private var modelConfig: LLMModelConfiguration?
    private let queue = DispatchQueue(label: "com.in-the-neighborhood.llama-service", qos: .userInitiated)
    
    // MARK: - Constants
    
    private static let batchSize = 512
    private static let maxGPULayers: Int32 = 999 // All layers to GPU
    private static let defaultThreadCount: UInt32 = 4
    private static let defaultSamplerSeed: UInt32 = 0
    private static let defaultMaxTokens = 256 // Shorter for query enhancement
    private static let agentMaxTokens = 512 // Room for JSON tool call or done
    private static let defaultTemperature: Double = 0.3 // Lower temperature for more deterministic JSON output
    
    /// Builds a multi-turn prompt from message history (system, user, assistant, tool_result).
    /// The result ends with the assistant header so the model generates the next message.
    /// Used by the agent loop; testable without loading the model.
    nonisolated static func buildMultiTurnPromptForAgent(messages: [(role: String, content: String)], chatTemplate: ChatTemplateFormat) -> String {
        let t = chatTemplate.tokens
        var parts: [String] = []
        if let begin = t.beginSequence { parts.append(begin) }
        var i = 0
        while i < messages.count {
            let role = messages[i].role
            let content = messages[i].content
            switch role {
            case "system":
                if let h = t.systemHeader { parts.append(h) }
                parts.append(content)
                if let e = t.endOfTurn { parts.append(e) }
            case "user":
                if let h = t.userHeader { parts.append(h) }
                parts.append(content)
                if let e = t.endOfTurn { parts.append(e) }
            case "assistant":
                if let h = t.assistantHeader { parts.append(h) }
                parts.append(content)
                if let e = t.endOfTurn { parts.append(e) }
            case "tool_result":
                if let h = t.userHeader { parts.append(h) }
                parts.append("Tool result: \(content)")
                if let e = t.endOfTurn { parts.append(e) }
            default:
                i += 1
                continue
            }
            i += 1
        }
        if let h = t.assistantHeader { parts.append(h) }
        return parts.joined()
    }
    
    // MARK: - Initialization
    
    public init() {
        // Check if model is available and trigger download if needed
        Task {
            if !LLMModelDownloadManager.shared.isModelAvailable() {
                LoggingService.shared.info(
                    "Model not found, triggering download",
                    category: "LlamaCppLLMService"
                )
                try? await LLMModelDownloadManager.shared.startDownloadIfNeeded()
            } else {
                LoggingService.shared.info(
                    "Model available, will load on first query",
                    category: "LlamaCppLLMService"
                )
            }
        }
    }
    
    // MARK: - LLMService Protocol
    
    public func enhanceQuery(_ query: String, metadata: ProductMetadata? = nil) async throws -> EnhancedQuery {
        // Validate input
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw LLMServiceError.invalidInput("Query cannot be empty")
        }
        
        // Try to use LLM if model is available, otherwise fall back to rule-based parsing
        if await modelIsAvailable() {
            do {
                let result = try await enhanceQueryWithLLM(trimmedQuery, metadata: metadata)
                print("[LlamaCppLLMService] enhanceQuery succeeded for query: '\(trimmedQuery)'")
                return result
            } catch {
                print("[LlamaCppLLMService] enhanceQuery failed for query: '\(trimmedQuery)', error: \(error.localizedDescription)")
                print("[LlamaCppLLMService] Error details: \(String(describing: error))")
                LoggingService.shared.warning(
                    "LLM enhancement failed, falling back to rule-based parsing: \(error)",
                    category: "LlamaCppLLMService"
                )
                // Fall through to rule-based parsing
            }
        } else {
            print("[LlamaCppLLMService] Model not available, using rule-based parsing for query: '\(trimmedQuery)'")
        }
        
        // Fallback to rule-based parsing
        return try parseQuery(trimmedQuery, metadata: metadata)
    }
    
    /// Determines what types of local stores would carry a given product
    /// Returns an array of store category names (e.g., ["bookstore", "furniture store"])
    public func determineStoreTypes(for productQuery: String, metadata: ProductMetadata? = nil) async throws -> [String] {
        // Validate input
        let trimmedQuery = productQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }
        
        // #region agent log
        logToFile([
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "Y",
            "location": "LlamaCppLLMService.swift:74",
            "message": "determineStoreTypes called",
            "data": [
                "productQuery": trimmedQuery,
                "modelAvailable": await modelIsAvailable()
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ])
        // #endregion
        
        // Try to use LLM if model is available, otherwise return empty array
        if await modelIsAvailable() {
            do {
                let result = try await determineStoreTypesWithLLM(trimmedQuery, metadata: metadata)
                // #region agent log
                logToFile([
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "Z",
                    "location": "LlamaCppLLMService.swift:86",
                    "message": "determineStoreTypesWithLLM succeeded",
                    "data": [
                        "resultCount": result.count,
                        "result": result
                    ],
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ])
                // #endregion
                return result
            } catch {
                // #region agent log
                logToFile([
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "AA",
                    "location": "LlamaCppLLMService.swift:88",
                    "message": "determineStoreTypesWithLLM failed",
                    "data": [
                        "error": error.localizedDescription,
                        "errorDescription": String(describing: error)
                    ],
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ])
                // #endregion
                LoggingService.shared.warning(
                    "LLM store type detection failed, falling back to empty array: \(error)",
                    category: "LlamaCppLLMService"
                )
                return []
            }
        }
        
        // Fallback: return empty array if model unavailable
        return []
    }
    
    // MARK: - Private Methods
    
    private func modelIsAvailable() async -> Bool {
        return LLMModelDownloadManager.shared.isModelAvailable()
    }
    
    private func enhanceQueryWithLLM(_ query: String, metadata: ProductMetadata?) async throws -> EnhancedQuery {
        // All llama.cpp operations must run on the serial queue
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: LLMServiceError.modelUnavailable)
                    return
                }
                
                do {
                    // If user changed selected model, unload so we load the new one
                    self.ensureLoadedModelMatchesSelection()
                    // Ensure model is loaded (uses selected model)
                    if !self.isModelLoaded() {
                        try self.loadModelSync()
                    }
                    
                    guard let model = self.llamaModel, let context = self.llamaContext else {
                        throw LLMServiceError.modelNotLoaded
                    }
                    
                    // Build prompt for query enhancement
                    let prompt = self.buildQueryEnhancementPrompt(query: query, metadata: metadata)
                    
                    // Console log the prompt
                    print("[LlamaCppLLMService] Sending prompt to LLM for query: '\(query)'")
                    print("[LlamaCppLLMService] Prompt (first 500 chars): \(String(prompt.prefix(500)))")
                    if prompt.count > 500 {
                        print("[LlamaCppLLMService] Prompt (full, \(prompt.count) chars): \(prompt)")
                    }
                    
                    // #region agent log
                    self.logToFile([
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "I",
                        "location": "LlamaCppLLMService.swift:126",
                        "message": "Prompt being sent to LLM",
                        "data": [
                            "promptLength": prompt.count,
                            "promptPreview": String(prompt.prefix(300)),
                            "promptFull": prompt,
                            "query": query
                        ],
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ])
                    // #endregion
                    
                    // #region agent log
                    self.logToFile([
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "X",
                        "location": "LlamaCppLLMService.swift:147",
                        "message": "About to call generateResponse",
                        "data": [
                            "promptLength": prompt.count,
                            "maxTokens": Self.defaultMaxTokens
                        ],
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ])
                    // #endregion
                    
                    // Generate response
                    let response: String
                    do {
                        response = try self.generateResponse(
                            prompt: prompt,
                            context: context,
                            model: model,
                            maxTokens: Self.defaultMaxTokens,
                            temperature: Self.defaultTemperature
                        )
                    } catch {
                        // #region agent log
                        if let logData = try? JSONSerialization.data(withJSONObject: [
                            "sessionId": "debug-session",
                            "runId": "run1",
                            "hypothesisId": "S",
                            "location": "LlamaCppLLMService.swift:148",
                            "message": "generateResponse threw error",
                            "data": [
                                "error": error.localizedDescription,
                                "errorDescription": String(describing: error)
                            ],
                            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                        ]), let logString = String(data: logData, encoding: .utf8) {
                            try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
                        }
                        // #endregion
                        throw error
                    }
                    
                    // Console log the response
                    print("[LlamaCppLLMService] Raw LLM response received, length: \(response.count)")
                    print("[LlamaCppLLMService] Response preview: \(String(response.prefix(200)))")
                    if response.count > 200 {
                        print("[LlamaCppLLMService] Response full: \(response)")
                    }
                    
                    // #region agent log
                    self.logToFile([
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "A",
                        "location": "LlamaCppLLMService.swift:177",
                        "message": "Raw LLM response received",
                        "data": [
                            "responseLength": response.count,
                            "responsePreview": String(response.prefix(500)),
                            "responseFull": response,
                            "containsOpenBrace": response.contains("{"),
                            "containsCloseBrace": response.contains("}"),
                            "containsJson": response.contains("json") || response.contains("JSON")
                        ],
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ])
                    // #endregion
                    
                    // Parse JSON response to EnhancedQuery
                    print("[LlamaCppLLMService] About to parse JSON response, length: \(response.count)")
                    let enhanced: EnhancedQuery
                    do {
                        enhanced = try self.parseJSONResponse(response, originalQuery: query)
                        print("[LlamaCppLLMService] parseJSONResponse succeeded")
                    } catch {
                        // Console log the error
                        print("[LlamaCppLLMService] parseJSONResponse threw error: \(error.localizedDescription)")
                        print("[LlamaCppLLMService] Error response was: \(response)")
                        
                        // #region agent log
                        self.logToFile([
                            "sessionId": "debug-session",
                            "runId": "run1",
                            "hypothesisId": "T",
                            "location": "LlamaCppLLMService.swift:201",
                            "message": "parseJSONResponse threw error",
                            "data": [
                                "error": error.localizedDescription,
                                "errorDescription": String(describing: error),
                                "responseLength": response.count,
                                "responsePreview": String(response.prefix(500)),
                                "responseFull": response
                            ],
                            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                        ])
                        // #endregion
                        throw error
                    }
                    
                    continuation.resume(returning: enhanced)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Generates the next assistant message from multi-turn agent messages (used by SearchAgent).
    /// Ensures model is loaded, builds prompt with buildMultiTurnPromptForAgent, runs inference.
    public func generateFromAgentMessages(messages: [(role: String, content: String)]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: LLMServiceError.modelNotLoaded)
                    return
                }
                do {
                    self.ensureLoadedModelMatchesSelection()
                    if !self.isModelLoaded() {
                        try self.loadModelSync()
                    }
                    guard let model = self.llamaModel, let context = self.llamaContext else {
                        continuation.resume(throwing: LLMServiceError.modelNotLoaded)
                        return
                    }
                    let config = self.modelConfig ?? LLMModelCatalog.shared.defaultModel
                    let prompt = Self.buildMultiTurnPromptForAgent(messages: messages, chatTemplate: config.chatTemplate)
                    let response = try self.generateResponse(
                        prompt: prompt,
                        context: context,
                        model: model,
                        maxTokens: Self.agentMaxTokens,
                        temperature: Self.defaultTemperature
                    )
                    continuation.resume(returning: response)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func determineStoreTypesWithLLM(_ productQuery: String, metadata: ProductMetadata?) async throws -> [String] {
        // All llama.cpp operations must run on the serial queue
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }
                
                do {
                    // If user changed selected model, unload so we load the new one
                    self.ensureLoadedModelMatchesSelection()
                    // Ensure model is loaded (uses selected model)
                    if !self.isModelLoaded() {
                        try self.loadModelSync()
                    }
                    
                    guard let model = self.llamaModel, let context = self.llamaContext else {
                        throw LLMServiceError.modelNotLoaded
                    }
                    
                    // Build prompt for store type detection
                    let prompt = self.buildStoreTypeDetectionPrompt(productQuery: productQuery, metadata: metadata)
                    
                    // Console log the prompt
                    print("[LlamaCppLLMService] Sending store categories prompt for product: '\(productQuery)'")
                    print("[LlamaCppLLMService] Store categories prompt (first 500 chars): \(String(prompt.prefix(500)))")
                    if prompt.count > 500 {
                        print("[LlamaCppLLMService] Store categories prompt (full, \(prompt.count) chars): \(prompt)")
                    }
                    
                    // Generate response
                    let response = try self.generateResponse(
                        prompt: prompt,
                        context: context,
                        model: model,
                        maxTokens: Self.defaultMaxTokens,
                        temperature: Self.defaultTemperature
                    )
                    
                    // #region agent log
                    if let logData = try? JSONSerialization.data(withJSONObject: [
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "J",
                        "location": "LlamaCppLLMService.swift:211",
                        "message": "Store categories - Raw LLM response received",
                        "data": [
                            "responseLength": response.count,
                            "responsePreview": String(response.prefix(500)),
                            "responseFull": response,
                            "containsOpenBrace": response.contains("{"),
                            "containsBracket": response.contains("["),
                            "productQuery": productQuery
                        ],
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ]), let logString = String(data: logData, encoding: .utf8) {
                        try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
                    }
                    // #endregion
                    
                    // Parse JSON response to extract store categories
                    let categories = try self.parseStoreCategoriesResponse(response)
                    
                    continuation.resume(returning: categories)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    nonisolated private func isModelLoaded() -> Bool {
        return llamaContext != nil && llamaModel != nil
    }
    
    /// Unloads the current model and context. Call before loading a different model.
    nonisolated private func unloadModelSync() {
        if let context = llamaContext {
            llama_free(context)
            llamaContext = nil
        }
        if let model = llamaModel {
            llama_model_free(model)
            llamaModel = nil
        }
        modelConfig = nil
    }
    
    nonisolated private func loadModelSync() throws {
        // Skip if already loaded (and no switch requested; caller handles switch via unload first)
        if isModelLoaded() {
            return
        }
        
        // Initialize backend (only once per process)
        if !backendInitialized {
            llama_backend_init()
            backendInitialized = true
            LoggingService.shared.debug(
                "Llama backend initialized",
                category: "LlamaCppLLMService"
            )
        }
        
        let downloadManager = LLMModelDownloadManager.shared
        let selectedID = downloadManager.selectedModelID()
        let catalog = LLMModelCatalog.shared
        
        // Use selected model config, fall back to default for config only (path still uses selected)
        let configToUse = catalog.model(for: selectedID) ?? catalog.defaultModel
        modelConfig = configToUse
        
        // Find model file for selected model (getModelPath() uses selectedModelID())
        guard let pathURL = downloadManager.getModelPath() else {
            LoggingService.shared.info(
                "Selected model '\(selectedID.rawValue)' not downloaded, using rule-based fallback",
                category: "LlamaCppLLMService"
            )
            modelConfig = nil
            throw LLMServiceError.modelNotFound
        }
        let modelPath = pathURL.path
        
        // Validate file exists
        guard FileManager.default.fileExists(atPath: modelPath) else {
            modelConfig = nil
            throw LLMServiceError.modelNotFound
        }
        
        // Create model parameters
        var modelParams = llama_model_default_params()
        
        // Enable Metal GPU acceleration on iOS devices (not simulator)
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0 // CPU-only on simulator
        #else
        modelParams.n_gpu_layers = Self.maxGPULayers
        #endif
        
        // Load model
        guard let model = llama_model_load_from_file(modelPath, modelParams) else {
            modelConfig = nil
            throw LLMServiceError.modelLoadFailed("Failed to load model from \(modelPath)")
        }
        
        llamaModel = model
        
        // Create context
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(configToUse.contextWindow)
        contextParams.n_batch = UInt32(Self.batchSize)
        contextParams.n_threads = Int32(Self.defaultThreadCount)
        
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            llamaModel = nil
            modelConfig = nil
            throw LLMServiceError.modelLoadFailed("Failed to create context")
        }
        
        llamaContext = context
        
        LoggingService.shared.info(
            "Model loaded successfully: \(configToUse.id.displayName)",
            category: "LlamaCppLLMService"
        )
    }
    
    nonisolated private func findModelPath() throws -> String {
        let downloadManager = LLMModelDownloadManager.shared
        if let modelPath = downloadManager.getModelPath() {
            return modelPath.path
        }
        throw LLMServiceError.modelNotFound
    }
    
    /// If the user changed the selected model, unload current model so next load uses the new one.
    nonisolated private func ensureLoadedModelMatchesSelection() {
        let selectedID = LLMModelDownloadManager.shared.selectedModelID()
        if isModelLoaded(), let currentID = modelConfig?.id, currentID != selectedID {
            unloadModelSync()
        }
    }
    
    nonisolated private func buildQueryEnhancementPrompt(query: String, metadata: ProductMetadata?) -> String {
        // Build a prompt that asks the LLM to extract structured information from the query
        // and return it as JSON
        let config = modelConfig ?? LLMModelCatalog.shared.defaultModel
        let templateTokens = config.chatTemplate.tokens
        
        // Build metadata context section if metadata is available
        var metadataContext = ""
        if let metadata = metadata, !metadata.isEmpty {
            var metadataParts: [String] = []
            
            if let isbn = metadata.isbn {
                metadataParts.append("ISBN: \(isbn) (indicates this is a book)")
            }
            if let author = metadata.author {
                metadataParts.append("Author: \(author) (indicates this is a book or media)")
            }
            if let sku = metadata.sku {
                metadataParts.append("SKU: \(sku) (indicates this is a specific product)")
            }
            if let asin = metadata.asin {
                metadataParts.append("ASIN: \(asin) (indicates this is an Amazon product)")
            }
            if let brand = metadata.brand {
                metadataParts.append("Brand: \(brand) (indicates manufacturer)")
            }
            if let artist = metadata.artist {
                metadataParts.append("Artist: \(artist) (indicates this is media/music)")
            }
            
            if !metadataParts.isEmpty {
                metadataContext = "\n\nAdditional context about the product:\n" + metadataParts.joined(separator: "\n") + "\n\nUse this metadata to help determine the product type and categories. For example:\n- ISBN or Author present → productType: 'book', categories: ['bookstore']\n- SKU or ASIN present → productType: specific product name, categories: appropriate retail stores\n- Brand present → productType: brand + product name, categories: stores that sell that brand"
            }
        }
        
        // Build system prompt
        let systemPrompt = """
        You are a JSON API. You MUST respond with ONLY valid JSON. Do not include any explanations, conversation, or other text.
        
        Extract structured information from the user's search query and return it as a JSON object with these fields:
        - productType: The main product or item (e.g., "office chair", "bicycle", "book")
        - categories: Array of business categories (e.g., ["furniture store", "office supply"], ["bookstore"], ["sporting goods"])
        - priceMax: Maximum price if mentioned (number, or null)
        - condition: Product condition if mentioned ("new", "used", "refurbished", or null)
        
        IMPORTANT: Pay attention to metadata clues:
        - ISBN numbers indicate books → productType should be "book" or book title, categories should include "bookstore"
        - Author names indicate books or media → productType should reflect the book/media title, categories should include "bookstore" or "media store"
        - SKU numbers indicate specific products → productType should be the specific product name
        - ASIN indicates Amazon products → productType should be the specific product name
        - Brand names indicate manufacturer → include brand in productType if relevant
        
        Examples:
        - Query: "The color purple" with ISBN: "9780143135692" → {"productType": "book", "categories": ["bookstore"], "priceMax": null, "condition": null}
        - Query: "The color purple" with Author: "Alice Walker" → {"productType": "book", "categories": ["bookstore"], "priceMax": null, "condition": null}
        - Query: "office chair" with SKU: "OC-12345" → {"productType": "office chair", "categories": ["furniture store", "office supply"], "priceMax": null, "condition": null}
        
        Your response must be ONLY the JSON object starting with { and ending with }. No other text.
        """ + metadataContext
        
        // Build user prompt - be very explicit
        let userPrompt = "Query: \"\(query)\". Return JSON only:"
        
        // Format according to chat template
        switch config.chatTemplate {
        case .llama32:
            return """
            \(templateTokens.beginSequence ?? "")
            \(templateTokens.systemHeader ?? "")\(systemPrompt)\(templateTokens.endOfTurn ?? "")
            \(templateTokens.userHeader ?? "")\(userPrompt)\(templateTokens.endOfTurn ?? "")
            \(templateTokens.assistantHeader ?? "")
            """
        case .qwen2:
            return """
            \(templateTokens.systemHeader ?? "")\(systemPrompt)\(templateTokens.endOfTurn ?? "")
            \(templateTokens.userHeader ?? "")\(userPrompt)\(templateTokens.endOfTurn ?? "")
            \(templateTokens.assistantHeader ?? "")
            """
        case .tinyLlama:
            return """
            \(templateTokens.systemHeader ?? "")\(systemPrompt)\(templateTokens.endOfTurn ?? "")
            \(templateTokens.userHeader ?? "")\(userPrompt)\(templateTokens.endOfTurn ?? "")
            \(templateTokens.assistantHeader ?? "")
            """
        case .mistral:
            return """
            \(templateTokens.beginSequence ?? "")
            \(templateTokens.instructStart ?? "")\(systemPrompt)\n\(userPrompt)\(templateTokens.instructEnd ?? "")
            """
        case .phi:
            return """
            \(templateTokens.instructStart ?? "")\(systemPrompt)\n\(userPrompt)\(templateTokens.instructEnd ?? "")
            """
        }
    }
    
    nonisolated private func buildStoreTypeDetectionPrompt(productQuery: String, metadata: ProductMetadata?) -> String {
        // Build a prompt that asks the LLM what types of local stores would carry a product
        let config = modelConfig ?? LLMModelCatalog.shared.defaultModel
        let templateTokens = config.chatTemplate.tokens
        
        // Build metadata context section if metadata is available
        var metadataContext = ""
        if let metadata = metadata, !metadata.isEmpty {
            var metadataParts: [String] = []
            
            if let isbn = metadata.isbn {
                metadataParts.append("ISBN: \(isbn) (indicates this is a book)")
            }
            if let author = metadata.author {
                metadataParts.append("Author: \(author) (indicates this is a book or media)")
            }
            if let sku = metadata.sku {
                metadataParts.append("SKU: \(sku) (indicates this is a specific product)")
            }
            if let asin = metadata.asin {
                metadataParts.append("ASIN: \(asin) (indicates this is an Amazon product)")
            }
            if let brand = metadata.brand {
                metadataParts.append("Brand: \(brand) (indicates manufacturer)")
            }
            
            if !metadataParts.isEmpty {
                metadataContext = "\n\nAdditional context about the product:\n" + metadataParts.joined(separator: "\n") + "\n\nUse this metadata to help determine store types. For example:\n- ISBN or Author present → storeCategories: ['bookstore']\n- SKU or ASIN present → storeCategories: appropriate retail stores for that product type"
            }
        }
        
        // Build system prompt
        let systemPrompt = """
        You are a retail assistant. Determine what types of local stores would carry a given product.
        
        Return a JSON object with a single field:
        - storeCategories: An array of store category names that are relevant to the specific product
        
        IMPORTANT: Only return store categories that are actually relevant to the specific product being asked about. Do not include generic or example categories. Base your response solely on the product provided.
        
        Pay attention to metadata clues:
        - ISBN numbers indicate books → storeCategories should include "bookstore"
        - Author names indicate books or media → storeCategories should include "bookstore" or "media store"
        - SKU or ASIN indicate specific products → determine appropriate retail stores based on product type
        
        Return valid JSON only, no explanation. If you cannot determine store types, return an empty array.
        """ + metadataContext
        
        // Build user prompt
        let userPrompt = "What types of local stores would carry this product: \"\(productQuery)\"?"
        
        // Format according to chat template
        switch config.chatTemplate {
        case .llama32:
            return """
            \(templateTokens.beginSequence ?? "")
            \(templateTokens.systemHeader ?? "")\(systemPrompt)\(templateTokens.endOfTurn ?? "")
            \(templateTokens.userHeader ?? "")\(userPrompt)\(templateTokens.endOfTurn ?? "")
            \(templateTokens.assistantHeader ?? "")
            """
        case .qwen2:
            return """
            \(templateTokens.systemHeader ?? "")\(systemPrompt)\(templateTokens.endOfTurn ?? "")
            \(templateTokens.userHeader ?? "")\(userPrompt)\(templateTokens.endOfTurn ?? "")
            \(templateTokens.assistantHeader ?? "")
            """
        case .tinyLlama:
            return """
            \(templateTokens.systemHeader ?? "")\(systemPrompt)\(templateTokens.endOfTurn ?? "")
            \(templateTokens.userHeader ?? "")\(userPrompt)\(templateTokens.endOfTurn ?? "")
            \(templateTokens.assistantHeader ?? "")
            """
        case .mistral:
            return """
            \(templateTokens.beginSequence ?? "")
            \(templateTokens.instructStart ?? "")\(systemPrompt)\n\(userPrompt)\(templateTokens.instructEnd ?? "")
            """
        case .phi:
            return """
            \(templateTokens.instructStart ?? "")\(systemPrompt)\n\(userPrompt)\(templateTokens.instructEnd ?? "")
            """
        }
    }
    
    nonisolated private func generateResponse(
        prompt: String,
        context: OpaquePointer,
        model: OpaquePointer,
        maxTokens: Int,
        temperature: Double
    ) throws -> String {
        print("[LlamaCppLLMService] generateResponse: Starting, prompt length: \(prompt.count), maxTokens: \(maxTokens)")
        
        // Tokenize prompt
        let tokens = tokenize(prompt, context: context, model: model)
        print("[LlamaCppLLMService] generateResponse: Tokenized, got \(tokens.count) tokens")
        guard !tokens.isEmpty else {
            throw LLMServiceError.inferenceFailed("Failed to tokenize prompt", reason: .transientFailure)
        }
        
        // Run inference
        print("[LlamaCppLLMService] generateResponse: Starting runInference")
        let generatedTokens = try runInference(
            context: context,
            promptTokens: tokens,
            maxTokens: maxTokens,
            temperature: temperature
        )
        print("[LlamaCppLLMService] generateResponse: runInference completed, got \(generatedTokens.count) tokens")
        
        // Decode tokens to text
        print("[LlamaCppLLMService] generateResponse: Decoding \(generatedTokens.count) tokens to text")
        var response = decode(generatedTokens, context: context)
        print("[LlamaCppLLMService] generateResponse: Decoded response length: \(response.count), preview: \(String(response.prefix(100)))")
        
        // #region agent log
        logToFile([
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "U",
            "location": "LlamaCppLLMService.swift:450",
            "message": "After decode, before filtering",
            "data": [
                "responseLength": response.count,
                "responsePreview": String(response.prefix(500)),
                "responseFull": response,
                "generatedTokenCount": generatedTokens.count
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ])
        // #endregion
        
        if response.isEmpty && generatedTokens.count > 0 {
            // #region agent log
            if let logData = try? JSONSerialization.data(withJSONObject: [
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "V",
                "location": "LlamaCppLLMService.swift:422",
                "message": "Empty response after decode",
                "data": [
                    "generatedTokenCount": generatedTokens.count,
                    "firstFewTokens": generatedTokens.prefix(10).map { String($0) }
                ],
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]), let logString = String(data: logData, encoding: .utf8) {
                try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
            }
            // #endregion
            throw LLMServiceError.inferenceFailed(
                "Generated \(generatedTokens.count) tokens but failed to decode",
                reason: .decodingError
            )
        }
        
        // Filter out Llama special tokens that appear as text in the response
        print("[LlamaCppLLMService] generateResponse: Filtering special tokens")
        response = filterSpecialTokens(from: response)
        print("[LlamaCppLLMService] generateResponse: After filtering, response length: \(response.count), preview: \(String(response.prefix(100)))")
        
        // #region agent log
        logToFile([
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "W",
            "location": "LlamaCppLLMService.swift:460",
            "message": "After filtering special tokens",
            "data": [
                "responseLength": response.count,
                "responsePreview": String(response.prefix(500)),
                "responseFull": response
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ])
        // #endregion
        
        print("[LlamaCppLLMService] generateResponse: Returning response, length: \(response.count)")
        return response
    }
    
    nonisolated private func tokenize(_ text: String, context: OpaquePointer, model: OpaquePointer) -> [Int32] {
        guard let vocab = llama_model_get_vocab(model) else {
            return []
        }
        
        let stringLength = text.utf8.count
        let maxTokens = stringLength + 1
        var tokens = [Int32](repeating: 0, count: maxTokens)
        
        let tokenCount = text.withCString { cString in
            llama_tokenize(
                vocab,
                cString,
                Int32(stringLength),
                &tokens,
                Int32(maxTokens),
                true,  // add_special
                false  // parse_special
            )
        }
        
        return Array(tokens.prefix(Int(tokenCount)))
    }
    
    nonisolated private func decode(_ tokens: [Int32], context: OpaquePointer) -> String {
        var result = ""
        guard let model = llama_get_model(context),
              let vocab = llama_model_get_vocab(model) else {
            return result
        }
        
        for token in tokens {
            var buffer = [CChar](repeating: 0, count: 64)
            let length = llama_token_to_piece(
                vocab,
                token,
                &buffer,
                64,
                0,
                false
            )
            
            if length > 0 {
                let actualLength = min(Int(length), 63)
                buffer[actualLength] = 0
                if let piece = String(cString: buffer, encoding: .utf8) {
                    result += piece
                }
            }
        }
        
        return result
    }
    
    nonisolated private func runInference(
        context: OpaquePointer,
        promptTokens: [Int32],
        maxTokens: Int,
        temperature: Double
    ) throws -> [Int32] {
        if Task.isCancelled {
            throw LLMServiceError.inferenceFailed("Inference cancelled", reason: .transientFailure)
        }
        
        guard let model = llama_get_model(context),
              let vocab = llama_model_get_vocab(model) else {
            throw LLMServiceError.inferenceFailed("Failed to get model/vocab", reason: .modelStateCorruption)
        }
        
        // Clear KV cache from previous queries to avoid sequence position conflicts
        // This prevents errors like "inconsistent sequence positions: X = 323, Y = 0"
        if let memory = llama_get_memory(context) {
            // Remove all tokens from sequence 0 (p0 = -1 means from start, p1 = -1 means to end)
            _ = llama_memory_seq_rm(memory, 0, -1, -1)
        }
        
        // Process prompt tokens in batches
        let maxBatchSize = Self.batchSize
        var batch = llama_batch_init(Int32(min(promptTokens.count, maxBatchSize)), 0, 1)
        defer { llama_batch_free(batch) }
        
        var allocatedSeqIds: [UnsafeMutablePointer<Int32>] = []
        defer {
            for ptr in allocatedSeqIds {
                ptr.deallocate()
            }
        }
        
        // Process prompt
        var processedTokens = 0
        var lastBatchSize = 0
        
        while processedTokens < promptTokens.count {
            if Task.isCancelled {
                throw LLMServiceError.inferenceFailed("Inference cancelled during prompt processing", reason: .transientFailure)
            }
            
            batch.n_tokens = 0
            let remainingTokens = promptTokens.count - processedTokens
            let batchSize = min(remainingTokens, maxBatchSize)
            
            for i in 0..<batchSize {
                let tokenIndex = processedTokens + i
                let token = promptTokens[tokenIndex]
                let pos = Int32(tokenIndex)
                let isLastPromptToken = (processedTokens + batchSize >= promptTokens.count) && (i == batchSize - 1)
                
                let batchPos = Int(batch.n_tokens)
                
                if batch.seq_id[batchPos] == nil {
                    let seqIdPtr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
                    seqIdPtr[0] = 0
                    batch.seq_id[batchPos] = seqIdPtr
                    allocatedSeqIds.append(seqIdPtr)
                } else {
                    batch.seq_id[batchPos]![0] = 0
                }
                
                batch.token[batchPos] = token
                batch.pos[batchPos] = pos
                batch.n_seq_id[batchPos] = 1
                batch.logits[batchPos] = isLastPromptToken ? 1 : 0
                batch.n_tokens += 1
            }
            
            lastBatchSize = batchSize
            
            if llama_decode(context, batch) != 0 {
                throw LLMServiceError.inferenceFailed("Failed to process prompt batch", reason: .transientFailure)
            }
            
            processedTokens += batchSize
        }
        
        guard lastBatchSize > 0,
              llama_get_logits_ith(context, Int32(lastBatchSize - 1)) != nil else {
            throw LLMServiceError.inferenceFailed("Failed to get logits from prompt", reason: .modelStateCorruption)
        }
        
        // Generate tokens
        var generatedTokens: [Int32] = []
        var n_cur = promptTokens.count
        
        // Sample first token
        var nextToken = sampleToken(context: context, model: model, vocab: vocab, temperature: Float(temperature), logitsIndex: Int32(lastBatchSize - 1))
        
        if llama_vocab_is_eog(vocab, nextToken) {
            return []
        }
        
        // Check first token - if it's clearly not starting JSON, stop early
        let firstTokenText = decode([nextToken], context: context)
        if shouldStopOnToken(firstTokenText) {
            return []
        }
        
        generatedTokens.append(nextToken)
        
        // Check if first few tokens indicate conversation format instead of JSON
        if generatedTokens.count <= 3 {
            let earlyResponse = decode(generatedTokens, context: context)
            if shouldStopOnResponse(earlyResponse) && !earlyResponse.contains("{") {
                return []
            }
        }
        
        // Prepare batch for generation
        batch.n_tokens = 0
        if batch.seq_id[0] == nil {
            let seqIdPtr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
            seqIdPtr[0] = 0
            batch.seq_id[0] = seqIdPtr
            allocatedSeqIds.append(seqIdPtr)
        } else {
            batch.seq_id[0]![0] = 0
        }
        
        batch.token[0] = nextToken
        batch.pos[0] = Int32(n_cur)
        batch.n_seq_id[0] = 1
        batch.logits[0] = 1
        batch.n_tokens = 1
        
        if llama_decode(context, batch) != 0 {
            throw LLMServiceError.inferenceFailed("Failed to decode first generated token", reason: .decodingError)
        }
        
        n_cur += 1
        
        // Autoregressive generation
        for iteration in 1..<maxTokens {
            if Task.isCancelled {
                throw LLMServiceError.inferenceFailed("Inference cancelled during generation", reason: .transientFailure)
            }
            
            guard llama_get_logits_ith(context, 0) != nil else {
                throw LLMServiceError.inferenceFailed("Failed to get logits at iteration \(iteration)", reason: .modelStateCorruption)
            }
            
            nextToken = sampleToken(context: context, model: model, vocab: vocab, temperature: Float(temperature), logitsIndex: 0)
            
            if llama_vocab_is_eog(vocab, nextToken) {
                break
            }
            
            // Check if this token decodes to a special token that should stop generation
            // Decode just this token to check
            let tokenText = decode([nextToken], context: context)
            if shouldStopOnToken(tokenText) {
                break
            }
            
            generatedTokens.append(nextToken)
            
            // Periodically check if accumulated response indicates we should stop
            // Check every 10 tokens to avoid performance impact
            if iteration % 10 == 0 {
                let currentResponse = decode(generatedTokens, context: context)
                if shouldStopOnResponse(currentResponse) {
                    break
                }
            }
            
            // Prepare next batch
            batch.n_tokens = 0
            if batch.seq_id[0] == nil {
                let seqIdPtr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
                seqIdPtr[0] = 0
                batch.seq_id[0] = seqIdPtr
                allocatedSeqIds.append(seqIdPtr)
            } else {
                batch.seq_id[0]![0] = 0
            }
            
            batch.token[0] = nextToken
            batch.pos[0] = Int32(n_cur)
            batch.n_seq_id[0] = 1
            batch.logits[0] = 1
            batch.n_tokens = 1
            
            if llama_decode(context, batch) != 0 {
                throw LLMServiceError.inferenceFailed("Failed to decode at iteration \(iteration)", reason: .decodingError)
            }
            
            n_cur += 1
        }
        
        return generatedTokens
    }
    
    /// Filters out Llama special tokens that appear as text in responses
    nonisolated private func filterSpecialTokens(from text: String) -> String {
        var filtered = text
        
        // List of special tokens to remove (Llama 3.2 format)
        let specialTokens = [
            "<|eot_json|>",
            "<|start_header_id|>",
            "<|end_header_id|>",
            "<|eot_id|>",
            "<|eom_id|>",
            "<|begin_of_text|>",
            "<|end_of_text|>"
        ]
        
        for token in specialTokens {
            filtered = filtered.replacingOccurrences(of: token, with: "")
        }
        
        // Remove any remaining patterns like "<|...|>"
        let pattern = "<\\|[^|]*\\|>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: filtered.utf16.count)
            filtered = regex.stringByReplacingMatches(in: filtered, options: [], range: range, withTemplate: "")
        }
        
        return filtered.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Determines if generation should stop when this token text is encountered
    nonisolated private func shouldStopOnToken(_ tokenText: String) -> Bool {
        // Stop on special tokens that indicate the response is complete
        let stopTokens = [
            "<|eot_json|>",
            "<|eot_id|>",
            "<|eom_id|>",
            "<|end_of_text|>",
            "<|start_header",  // Stop if we see conversation continuation
            "userExtract",     // Stop if model starts repeating user prompts
            "assistantHere"    // Stop if model starts conversation format
        ]
        
        return stopTokens.contains { tokenText.contains($0) }
    }
    
    /// Checks if the accumulated response so far indicates we should stop
    nonisolated private func shouldStopOnResponse(_ response: String) -> Bool {
        // Stop if we see patterns that indicate conversation continuation instead of JSON
        let stopPatterns = [
            "Here is the extracted information",
            "userExtract information",
            "assistantHere is",
            "<|start_header_id|>user",
            "<|start_header_id|>assistant",
            "userQuery:",
            "assistantQuery:"
        ]
        
        // Only stop if we don't have a JSON object yet
        if !response.contains("{") {
            // If we see conversation patterns and no JSON, stop immediately
            if stopPatterns.contains(where: { response.contains($0) }) {
                return true
            }
            // If response is getting long (200+ chars) and still no JSON, likely not generating JSON
            if response.count > 200 && !response.contains("{") {
                return true
            }
        }
        
        return false
    }
    
    nonisolated private func sampleToken(
        context: OpaquePointer,
        model: OpaquePointer,
        vocab: OpaquePointer,
        temperature: Float,
        logitsIndex: Int32
    ) -> Int32 {
        let n_vocab = llama_vocab_n_tokens(vocab)
        guard n_vocab > 0, logitsIndex >= 0,
              let logits = llama_get_logits_ith(context, logitsIndex),
              logits[0].isFinite else {
            return 0
        }
        
        let samplerParams = llama_sampler_chain_default_params()
        guard let sampler = llama_sampler_chain_init(samplerParams) else {
            return 0
        }
        defer { llama_sampler_free(sampler) }
        
        if temperature > 0.0 {
            guard let tempSampler = llama_sampler_init_temp(temperature) else {
                return 0
            }
            llama_sampler_chain_add(sampler, tempSampler)
            
            guard let distSampler = llama_sampler_init_dist(Self.defaultSamplerSeed) else {
                return 0
            }
            llama_sampler_chain_add(sampler, distSampler)
        } else {
            guard let greedySampler = llama_sampler_init_greedy() else {
                return 0
            }
            llama_sampler_chain_add(sampler, greedySampler)
        }
        
        let token = llama_sampler_sample(sampler, context, logitsIndex)
        guard token >= 0 && token < n_vocab else {
            return 0
        }
        
        return token
    }
    
    nonisolated private func parseJSONResponse(_ response: String, originalQuery: String) throws -> EnhancedQuery {
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "A",
            "location": "LlamaCppLLMService.swift:676",
            "message": "parseJSONResponse entry",
            "data": [
                "responseLength": response.count,
                "responsePreview": String(response.prefix(200))
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]), let logString = String(data: logData, encoding: .utf8) {
            try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
        }
        // #endregion
        
        // Clean response - extract JSON from response text
        var cleaned = cleanJSONResponse(response)
        
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "B",
            "location": "LlamaCppLLMService.swift:678",
            "message": "After initial cleanJSONResponse",
            "data": [
                "cleanedLength": cleaned.count,
                "cleanedPreview": String(cleaned.prefix(200)),
                "cleanedFull": cleaned
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]), let logString = String(data: logData, encoding: .utf8) {
            try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
        }
        // #endregion
        
        // Try to parse, and if it fails, try additional cleaning
        var json: [String: Any]? = nil
        var firstAttemptError: String? = nil
        
        // First attempt
        if let data = cleaned.data(using: .utf8) {
            do {
                json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                // #region agent log
                if let logData = try? JSONSerialization.data(withJSONObject: [
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "C",
                    "location": "LlamaCppLLMService.swift:686",
                    "message": "First parse attempt succeeded",
                    "data": ["jsonKeys": json?.keys.map { String($0) } ?? []],
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]), let logString = String(data: logData, encoding: .utf8) {
                    try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
                }
                // #endregion
            } catch {
                firstAttemptError = error.localizedDescription
                // #region agent log
                if let logData = try? JSONSerialization.data(withJSONObject: [
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "D",
                    "location": "LlamaCppLLMService.swift:688",
                    "message": "First parse attempt failed",
                    "data": [
                        "error": error.localizedDescription,
                        "errorDescription": String(describing: error),
                        "dataLength": data.count,
                        "dataPreview": String(data.prefix(200).map { Character(UnicodeScalar($0)) })
                    ],
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]), let logString = String(data: logData, encoding: .utf8) {
                    try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
                }
                // #endregion
            }
        }
        
        // If first attempt failed, try additional cleaning
        if json == nil {
            // Remove any trailing content after the JSON object
            cleaned = removeTrailingContent(from: cleaned)
            // #region agent log
            if let logData = try? JSONSerialization.data(withJSONObject: [
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "E",
                "location": "LlamaCppLLMService.swift:695",
                "message": "After removeTrailingContent",
                "data": [
                    "cleanedLength": cleaned.count,
                    "cleanedPreview": String(cleaned.prefix(200)),
                    "cleanedFull": cleaned
                ],
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]), let logString = String(data: logData, encoding: .utf8) {
                try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
            }
            // #endregion
            
            if let data = cleaned.data(using: .utf8) {
                do {
                    json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    // #region agent log
                    if let logData = try? JSONSerialization.data(withJSONObject: [
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "F",
                        "location": "LlamaCppLLMService.swift:698",
                        "message": "Second parse attempt succeeded",
                        "data": ["jsonKeys": json?.keys.map { String($0) } ?? []],
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ]), let logString = String(data: logData, encoding: .utf8) {
                        try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
                    }
                    // #endregion
                } catch {
                    // #region agent log
                    if let logData = try? JSONSerialization.data(withJSONObject: [
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "G",
                        "location": "LlamaCppLLMService.swift:700",
                        "message": "Second parse attempt also failed",
                        "data": [
                            "error": error.localizedDescription,
                            "errorDescription": String(describing: error),
                            "firstAttemptError": firstAttemptError ?? "none",
                            "dataLength": data.count,
                            "dataPreview": String(data.prefix(200).map { Character(UnicodeScalar($0)) })
                        ],
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ]), let logString = String(data: logData, encoding: .utf8) {
                        try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
                    }
                    // #endregion
                }
            }
        }
        
        guard let json = json else {
            // Check if response contains any JSON-like content
            let hasJsonStructure = cleaned.contains("{") || cleaned.contains("[")
            
            // #region agent log
            if let logData = try? JSONSerialization.data(withJSONObject: [
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "H",
                "location": "LlamaCppLLMService.swift:1027",
                "message": "All parse attempts failed, throwing error",
                "data": [
                    "originalResponseLength": response.count,
                    "originalResponsePreview": String(response.prefix(500)),
                    "originalResponseFull": response,
                    "finalCleanedLength": cleaned.count,
                    "finalCleanedPreview": String(cleaned.prefix(500)),
                    "finalCleaned": cleaned,
                    "firstAttemptError": firstAttemptError ?? "none",
                    "hasOpenBrace": cleaned.contains("{"),
                    "hasCloseBrace": cleaned.contains("}"),
                    "hasJsonStructure": hasJsonStructure,
                    "looksLikeConversation": response.contains("user") || response.contains("assistant") || response.contains("Here is")
                ],
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]), let logString = String(data: logData, encoding: .utf8) {
                try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
            }
            // #endregion
            
            // If there's no JSON structure at all, the model generated conversation instead of JSON
            if !hasJsonStructure {
                throw LLMServiceError.inferenceFailed("LLM generated conversation history instead of JSON", reason: .decodingError)
            } else {
                throw LLMServiceError.inferenceFailed("Failed to parse JSON response", reason: .decodingError)
            }
        }
        
        // Extract data from parsed JSON
        let productType: String? = json["productType"] as? String
        var categories: [String] = []
        if let cats = json["categories"] as? [String] {
            categories = cats
        }
        var priceMax: Double? = nil
        if let price = json["priceMax"] as? Double {
            priceMax = price
        } else if let price = json["priceMax"] as? Int {
            priceMax = Double(price)
        }
        var condition: ProductCondition? = nil
        if let condStr = json["condition"] as? String {
            switch condStr.lowercased() {
            case "new":
                condition = .new
            case "used":
                condition = .used
            case "refurbished":
                condition = .refurbished
            default:
                break
            }
        }
        
        return EnhancedQuery(
            original: originalQuery,
            productType: productType,
            categories: categories,
            priceMax: priceMax,
            condition: condition
        )
    }
    
    nonisolated private func parseStoreCategoriesResponse(_ response: String) throws -> [String] {
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "K",
            "location": "LlamaCppLLMService.swift:1000",
            "message": "parseStoreCategoriesResponse entry",
            "data": [
                "responseLength": response.count,
                "responsePreview": String(response.prefix(200))
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]), let logString = String(data: logData, encoding: .utf8) {
            try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
        }
        // #endregion
        
        // Clean response - extract JSON from response text
        var cleaned = cleanJSONResponse(response)
        
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "L",
            "location": "LlamaCppLLMService.swift:1002",
            "message": "Store categories - After cleanJSONResponse",
            "data": [
                "cleanedLength": cleaned.count,
                "cleanedPreview": String(cleaned.prefix(200)),
                "cleanedFull": cleaned
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]), let logString = String(data: logData, encoding: .utf8) {
            try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
        }
        // #endregion
        
        // Try to parse, and if it fails, try additional cleaning
        var json: [String: Any]? = nil
        var array: [String]? = nil
        var firstAttemptError: String? = nil
        
        // First attempt - try as object
        if let data = cleaned.data(using: .utf8) {
            do {
                json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                // #region agent log
                if let logData = try? JSONSerialization.data(withJSONObject: [
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "M",
                    "location": "LlamaCppLLMService.swift:1015",
                    "message": "Store categories - First parse as object succeeded",
                    "data": ["jsonKeys": json?.keys.map { String($0) } ?? []],
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]), let logString = String(data: logData, encoding: .utf8) {
                    try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
                }
                // #endregion
            } catch {
                firstAttemptError = error.localizedDescription
                // Try as array
                do {
                    array = try JSONSerialization.jsonObject(with: data) as? [String]
                    // #region agent log
                    if let logData = try? JSONSerialization.data(withJSONObject: [
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "N",
                        "location": "LlamaCppLLMService.swift:1020",
                        "message": "Store categories - First parse as array succeeded",
                        "data": ["arrayCount": array?.count ?? 0],
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ]), let logString = String(data: logData, encoding: .utf8) {
                        try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
                    }
                    // #endregion
                } catch {
                    // #region agent log
                    if let logData = try? JSONSerialization.data(withJSONObject: [
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "O",
                        "location": "LlamaCppLLMService.swift:1025",
                        "message": "Store categories - First parse attempts failed",
                        "data": [
                            "objectError": error.localizedDescription,
                            "firstAttemptError": firstAttemptError ?? "none"
                        ],
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ]), let logString = String(data: logData, encoding: .utf8) {
                        try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
                    }
                    // #endregion
                }
            }
        }
        
        // If first attempt failed, try additional cleaning
        if json == nil && array == nil {
            cleaned = removeTrailingContent(from: cleaned)
            // #region agent log
            if let logData = try? JSONSerialization.data(withJSONObject: [
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "P",
                "location": "LlamaCppLLMService.swift:1040",
                "message": "Store categories - After removeTrailingContent",
                "data": [
                    "cleanedLength": cleaned.count,
                    "cleanedPreview": String(cleaned.prefix(200)),
                    "cleanedFull": cleaned
                ],
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]), let logString = String(data: logData, encoding: .utf8) {
                try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
            }
            // #endregion
            
            if let data = cleaned.data(using: .utf8) {
                do {
                    json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                } catch {
                    // Try as array
                    do {
                        array = try JSONSerialization.jsonObject(with: data) as? [String]
                    } catch {
                        // #region agent log
                        if let logData = try? JSONSerialization.data(withJSONObject: [
                            "sessionId": "debug-session",
                            "runId": "run1",
                            "hypothesisId": "Q",
                            "location": "LlamaCppLLMService.swift:1050",
                            "message": "Store categories - Second parse attempts also failed",
                            "data": [
                                "error": error.localizedDescription,
                                "firstAttemptError": firstAttemptError ?? "none"
                            ],
                            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                        ]), let logString = String(data: logData, encoding: .utf8) {
                            try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
                        }
                        // #endregion
                    }
                }
            }
        }
        
        // Extract categories from object
        if let json = json {
            var categories: [String] = []
            // Handle both flat array [String] and nested array [[String]]
            if let cats = json["storeCategories"] as? [String] {
                categories = cats
            } else if let nestedCats = json["storeCategories"] as? [[String]] {
                // Flatten nested array
                categories = nestedCats.flatMap { $0 }
            } else if let anyCats = json["storeCategories"] as? [Any] {
                // Handle mixed array structure - extract strings from any nested structure
                for item in anyCats {
                    if let str = item as? String {
                        categories.append(str)
                    } else if let arr = item as? [String] {
                        categories.append(contentsOf: arr)
                    } else if let arr = item as? [Any] {
                        // Deep nested - extract strings recursively
                        for subItem in arr {
                            if let str = subItem as? String {
                                categories.append(str)
                            }
                        }
                    }
                }
            }
            print("[LlamaCppLLMService] parseStoreCategoriesResponse: Extracted \(categories.count) categories from object: \(categories)")
            return categories
        }
        
        // Or return array directly
        if let array = array {
            print("[LlamaCppLLMService] parseStoreCategoriesResponse: Extracted \(array.count) categories from array: \(array)")
            return array
        }
        
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "R",
            "location": "LlamaCppLLMService.swift:1075",
            "message": "Store categories - All parse attempts failed, throwing error",
            "data": [
                "originalResponseLength": response.count,
                "finalCleanedLength": cleaned.count,
                "finalCleaned": cleaned,
                "firstAttemptError": firstAttemptError ?? "none"
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]), let logString = String(data: logData, encoding: .utf8) {
            try? (logString + "\n").write(toFile: "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log", atomically: false, encoding: .utf8)
        }
        // #endregion
        
        throw LLMServiceError.inferenceFailed("Failed to parse store categories JSON", reason: .decodingError)
    }
    
    nonisolated private func cleanJSONResponse(_ response: String) -> String {
        // Extract JSON from response - look for JSON object boundaries
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks if present
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Filter out special tokens first
        cleaned = filterSpecialTokens(from: cleaned)
        
        // Find first { and use bracket matching to find the matching }
        // This handles cases where there's text before or after the JSON object
        if let startIndex = cleaned.firstIndex(of: "{") {
            var braceCount = 0
            var endIndex: String.Index? = nil
            
            for index in cleaned[startIndex...].indices {
                let char = cleaned[index]
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        endIndex = index
                        break
                    }
                }
            }
            
            if let endIndex = endIndex {
                cleaned = String(cleaned[startIndex...endIndex])
            } else {
                // Fallback: if bracket matching fails, try to find last }
                if let fallbackEndIndex = cleaned.lastIndex(of: "}") {
                    cleaned = String(cleaned[startIndex...fallbackEndIndex])
                }
            }
        } else {
            // If no { found, try to find JSON array
            if let startIndex = cleaned.firstIndex(of: "[") {
                var bracketCount = 0
                var endIndex: String.Index? = nil
                
                for index in cleaned[startIndex...].indices {
                    let char = cleaned[index]
                    if char == "[" {
                        bracketCount += 1
                    } else if char == "]" {
                        bracketCount -= 1
                        if bracketCount == 0 {
                            endIndex = index
                            break
                        }
                    }
                }
                
                if let endIndex = endIndex {
                    cleaned = String(cleaned[startIndex...endIndex])
                }
            }
        }
        
        return cleaned
    }
    
    /// Removes trailing content after a JSON object/array
    /// Handles cases where LLM adds explanatory text after the JSON
    nonisolated private func removeTrailingContent(from json: String) -> String {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If it starts with {, find the matching } and remove everything after
        if cleaned.first == "{" {
            var braceCount = 0
            var endIndex: String.Index? = nil
            
            for index in cleaned.indices {
                let char = cleaned[index]
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        endIndex = index
                        break
                    }
                }
            }
            
            if let endIndex = endIndex {
                // Include the closing brace, then stop
                let nextIndex = cleaned.index(after: endIndex)
                if nextIndex < cleaned.endIndex {
                    cleaned = String(cleaned[..<nextIndex])
                }
            }
        }
        // If it starts with [, find the matching ] and remove everything after
        else if cleaned.first == "[" {
            var bracketCount = 0
            var endIndex: String.Index? = nil
            
            for index in cleaned.indices {
                let char = cleaned[index]
                if char == "[" {
                    bracketCount += 1
                } else if char == "]" {
                    bracketCount -= 1
                    if bracketCount == 0 {
                        endIndex = index
                        break
                    }
                }
            }
            
            if let endIndex = endIndex {
                let nextIndex = cleaned.index(after: endIndex)
                if nextIndex < cleaned.endIndex {
                    cleaned = String(cleaned[..<nextIndex])
                }
            }
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    nonisolated private func parseQuery(_ query: String, metadata: ProductMetadata?) throws -> EnhancedQuery {
        // Basic rule-based parsing as fallback
        var productType: String?
        var categories: [String] = []
        var priceMax: Double?
        var condition: ProductCondition?
        
        let lowercased = query.lowercased()
        
        // Use metadata to improve categorization
        if let metadata = metadata {
            // ISBN indicates a book
            if metadata.isbn != nil {
                categories.append("bookstore")
                // Query is the book title
                productType = query.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Author indicates book or media
            else if metadata.author != nil {
                categories.append("bookstore")
                productType = query.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // SKU or ASIN indicates a specific product
            else if metadata.sku != nil || metadata.asin != nil {
                // Product type is the query itself
                productType = query.trimmingCharacters(in: .whitespacesAndNewlines)
                // Categories will be determined by keyword matching below
            }
            // Brand indicates manufacturer
            else if metadata.brand != nil {
                // Include brand in product type if not already present
                if let brand = metadata.brand, !lowercased.contains(brand.lowercased()) {
                    productType = "\(brand) \(query)".trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    productType = query.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            // Artist indicates media/music
            else if metadata.artist != nil {
                categories.append("media store")
                productType = query.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Extract price constraint
        if let priceMatch = lowercased.range(of: #"under\s+\$?(\d+)"#, options: .regularExpression) {
            let priceString = String(query[priceMatch])
            let numbers = priceString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let price = Double(numbers) {
                priceMax = price
            }
        }
        
        // Extract condition
        if lowercased.contains("used") {
            condition = .used
        } else if lowercased.contains("new") {
            condition = .new
        } else if lowercased.contains("refurbished") {
            condition = .refurbished
        }
        
        // Simple keyword-based category detection (only if not already set by metadata)
        if categories.isEmpty {
            if lowercased.contains("book") {
                categories.append("bookstore")
            }
            if lowercased.contains("bicycle") || lowercased.contains("bike") {
                categories.append("sporting goods")
            }
            if lowercased.contains("furniture") || lowercased.contains("chair") {
                categories.append("furniture store")
            }
            if lowercased.contains("office") {
                categories.append("office supply")
            }
        }
        
        // Extract product type (simplified - take last noun phrase) if not set by metadata
        if productType == nil {
            let words = query.components(separatedBy: .whitespaces)
            if words.count > 1 {
                productType = words.suffix(2).joined(separator: " ")
            } else {
                productType = words.first
            }
        }
        
        return EnhancedQuery(
            original: query,
            productType: productType,
            categories: categories,
            priceMax: priceMax,
            condition: condition
        )
    }
    
    /// Helper method to log to file reliably from background queue
    nonisolated private func logToFile(_ logDict: [String: Any]) {
        let logPath = "/Users/erich/git/github/erichchampion/in-the-neighborhood/.cursor/debug.log"
        guard let logData = try? JSONSerialization.data(withJSONObject: logDict),
              let logString = String(data: logData, encoding: .utf8) else {
            return
        }
        
        // Use FileHandle for reliable writing from background queue
        if FileManager.default.fileExists(atPath: logPath) {
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                if let data = (logString + "\n").data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            }
        } else {
            // Create file if it doesn't exist
            try? (logString + "\n").write(toFile: logPath, atomically: false, encoding: .utf8)
        }
    }
}
