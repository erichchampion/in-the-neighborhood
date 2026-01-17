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
    private static let defaultTemperature: Double = 0.3 // Lower temperature for more deterministic JSON output
    
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
    
    public func enhanceQuery(_ query: String) async throws -> EnhancedQuery {
        // Validate input
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw LLMServiceError.invalidInput("Query cannot be empty")
        }
        
        // Try to use LLM if model is available, otherwise fall back to rule-based parsing
        if await modelIsAvailable() {
            do {
                return try await enhanceQueryWithLLM(trimmedQuery)
            } catch {
                LoggingService.shared.warning(
                    "LLM enhancement failed, falling back to rule-based parsing: \(error)",
                    category: "LlamaCppLLMService"
                )
                // Fall through to rule-based parsing
            }
        }
        
        // Fallback to rule-based parsing
        return try parseQuery(trimmedQuery)
    }
    
    // MARK: - Private Methods
    
    private func modelIsAvailable() async -> Bool {
        return LLMModelDownloadManager.shared.isModelAvailable()
    }
    
    private func enhanceQueryWithLLM(_ query: String) async throws -> EnhancedQuery {
        // All llama.cpp operations must run on the serial queue
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: LLMServiceError.modelUnavailable)
                    return
                }
                
                do {
                    // Ensure model is loaded
                    if !self.isModelLoaded() {
                        try self.loadModelSync()
                    }
                    
                    guard let model = self.llamaModel, let context = self.llamaContext else {
                        throw LLMServiceError.modelNotLoaded
                    }
                    
                    // Build prompt for query enhancement
                    let prompt = self.buildQueryEnhancementPrompt(query: query)
                    
                    // Generate response
                    let response = try self.generateResponse(
                        prompt: prompt,
                        context: context,
                        model: model,
                        maxTokens: Self.defaultMaxTokens,
                        temperature: Self.defaultTemperature
                    )
                    
                    // Parse JSON response to EnhancedQuery
                    let enhanced = try self.parseJSONResponse(response, originalQuery: query)
                    
                    continuation.resume(returning: enhanced)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    nonisolated private func isModelLoaded() -> Bool {
        return llamaContext != nil && llamaModel != nil
    }
    
    nonisolated private func loadModelSync() throws {
        // Skip if already loaded
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
        
        // Get model configuration
        let catalog = LLMModelCatalog.shared
        let defaultModelConfig = catalog.defaultModel
        modelConfig = defaultModelConfig
        
        // Find model file
        let modelPath = try findModelPath()
        
        // Validate file exists
        guard FileManager.default.fileExists(atPath: modelPath) else {
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
            throw LLMServiceError.modelLoadFailed("Failed to load model from \(modelPath)")
        }
        
        llamaModel = model
        
        // Create context
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(defaultModelConfig.contextWindow)
        contextParams.n_batch = UInt32(Self.batchSize)
        contextParams.n_threads = Int32(Self.defaultThreadCount)
        
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            llamaModel = nil
            throw LLMServiceError.modelLoadFailed("Failed to create context")
        }
        
        llamaContext = context
        
        LoggingService.shared.info(
            "Model loaded successfully: \(defaultModelConfig.id.displayName)",
            category: "LlamaCppLLMService"
        )
    }
    
    nonisolated private func findModelPath() throws -> String {
        let downloadManager = LLMModelDownloadManager.shared
        
        // Try to get default model path
        if let modelPath = downloadManager.getModelPath() {
            return modelPath.path
        }
        
        throw LLMServiceError.modelNotFound
    }
    
    nonisolated private func buildQueryEnhancementPrompt(query: String) -> String {
        // Build a prompt that asks the LLM to extract structured information from the query
        // and return it as JSON
        let config = modelConfig ?? LLMModelCatalog.shared.defaultModel
        let templateTokens = config.chatTemplate.tokens
        
        // Build system prompt
        let systemPrompt = """
        You are a query enhancement assistant. Extract structured information from user search queries and return it as JSON.
        
        Return a JSON object with the following fields:
        - productType: The main product or item being searched for (e.g., "office chair", "bicycle")
        - categories: Array of relevant business categories (e.g., ["furniture store", "office supply"])
        - priceMax: Maximum price if mentioned (number, or null)
        - condition: Product condition if mentioned ("new", "used", "refurbished", or null)
        
        Only include fields that can be extracted from the query. Return valid JSON only, no explanation.
        """
        
        // Build user prompt
        let userPrompt = "Extract information from this search query: \"\(query)\""
        
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
        // Tokenize prompt
        let tokens = tokenize(prompt, context: context, model: model)
        guard !tokens.isEmpty else {
            throw LLMServiceError.inferenceFailed("Failed to tokenize prompt", reason: .transientFailure)
        }
        
        // Run inference
        let generatedTokens = try runInference(
            context: context,
            promptTokens: tokens,
            maxTokens: maxTokens,
            temperature: temperature
        )
        
        // Decode tokens to text
        let response = decode(generatedTokens, context: context)
        
        if response.isEmpty && generatedTokens.count > 0 {
            throw LLMServiceError.inferenceFailed(
                "Generated \(generatedTokens.count) tokens but failed to decode",
                reason: .decodingError
            )
        }
        
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
        
        generatedTokens.append(nextToken)
        
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
            
            generatedTokens.append(nextToken)
            
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
        // Clean response - extract JSON from response text
        let cleaned = cleanJSONResponse(response)
        
        guard let data = cleaned.data(using: .utf8) else {
            throw LLMServiceError.inferenceFailed("Failed to convert response to data", reason: .decodingError)
        }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            let productType: String? = json?["productType"] as? String
            var categories: [String] = []
            if let cats = json?["categories"] as? [String] {
                categories = cats
            }
            var priceMax: Double? = nil
            if let price = json?["priceMax"] as? Double {
                priceMax = price
            } else if let price = json?["priceMax"] as? Int {
                priceMax = Double(price)
            }
            var condition: ProductCondition? = nil
            if let condStr = json?["condition"] as? String {
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
        } catch {
            // If JSON parsing fails, fall back to rule-based parsing instead of throwing
            // This allows the search to continue even if the LLM response is malformed
            LoggingService.shared.warning(
                "Failed to parse JSON response, falling back to rule-based parsing: \(error)",
                category: "LlamaCppLLMService"
            )
            // Don't throw - instead return a fallback EnhancedQuery via parseQuery
            // The caller (enhanceQueryWithLLM) will throw, which will be caught in enhanceQuery
            // and fall back to parseQuery anyway, but we can simplify by calling parseQuery here
            // However, we can't call parseQuery from here as it's nonisolated and we're in a continuation
            // So we throw and let the error handling in enhanceQuery catch it
            throw LLMServiceError.inferenceFailed("Invalid JSON response: \(error.localizedDescription)", reason: .decodingError)
        }
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
        
        // Find first { and last }
        if let startIndex = cleaned.firstIndex(of: "{"),
           let endIndex = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[startIndex...endIndex])
        }
        
        return cleaned
    }
    
    nonisolated private func parseQuery(_ query: String) throws -> EnhancedQuery {
        // Basic rule-based parsing as fallback
        var productType: String?
        var categories: [String] = []
        var priceMax: Double?
        var condition: ProductCondition?
        
        let lowercased = query.lowercased()
        
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
        
        // Simple keyword-based category detection
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
        
        // Extract product type (simplified - take last noun phrase)
        let words = query.components(separatedBy: .whitespaces)
        if words.count > 1 {
            productType = words.suffix(2).joined(separator: " ")
        } else {
            productType = words.first
        }
        
        return EnhancedQuery(
            original: query,
            productType: productType,
            categories: categories,
            priceMax: priceMax,
            condition: condition
        )
    }
}
