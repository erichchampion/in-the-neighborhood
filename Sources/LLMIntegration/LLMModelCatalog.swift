import Foundation

/// Model identifiers for available LLM models optimized for query enhancement
public enum LLMModelID: String, Codable, CaseIterable, Sendable {
    // Recommended models for query enhancement (instruction-tuned, smaller size)
    case llama32_1BInstruct = "llama-3.2-1b-instruct"
    case qwen25_15BInstruct = "qwen2.5-1.5b-instruct"
    case phi3Mini4KInstruct = "phi-3-mini-4k-instruct"
    case qwen25_3BInstruct = "qwen2.5-3b-instruct"
    case ministral3BInstruct = "ministral-3-3b-instruct"
    
    // Legacy models (kept for backward compatibility, not recommended)
    case tinyLlama11BChat = "tinyllama-1.1b-chat"
    case qwen215BInstruct = "qwen2-1.5b-instruct"

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .llama32_1BInstruct:
            return "Llama 3.2 1B Instruct"
        case .qwen25_15BInstruct:
            return "Qwen2.5 1.5B Instruct"
        case .phi3Mini4KInstruct:
            return "Phi-3 Mini 3.8B"
        case .qwen25_3BInstruct:
            return "Qwen2.5 3B Instruct"
        case .ministral3BInstruct:
            return "Ministral 3B Instruct"
        case .tinyLlama11BChat:
            return "TinyLlama 1.1B Chat (Legacy)"
        case .qwen215BInstruct:
            return "Qwen2 1.5B Instruct (Legacy)"
        }
    }

    /// Brief description of the model
    var description: String {
        switch self {
        case .llama32_1BInstruct:
            return "Meta Llama 3.2 1B instruction-tuned model, Q4_K_M quantization (~800MB) - Optimized for query enhancement"
        case .qwen25_15BInstruct:
            return "Qwen2.5 1.5B instruction-tuned model, Q4_K_M quantization (~1GB) - Good balance of size and quality"
        case .phi3Mini4KInstruct:
            return "Microsoft Phi-3 Mini 3.8B instruction-tuned model, Q4_K_M quantization (~2.5GB)"
        case .qwen25_3BInstruct:
            return "Qwen2.5 3B instruction-tuned model, Q4_K_M quantization (~2GB)"
        case .ministral3BInstruct:
            return "Mistral AI Ministral 3B Instruct, Q4_K_M quantization (~2.15GB)"
        case .tinyLlama11BChat:
            return "TinyLlama 1.1B parameter chat model, Q4_K_M quantization (~669MB) - Legacy"
        case .qwen215BInstruct:
            return "Qwen2 1.5B instruction-tuned model, Q4_K_M quantization (~934MB) - Legacy"
        }
    }
}

/// Chat template format used by the model
enum ChatTemplateFormat: String, Codable, Sendable {
    case tinyLlama
    case qwen2
    case mistral
    case phi
    case llama32

    /// Format tokens for the template
    var tokens: ChatTemplateTokens {
        switch self {
        case .tinyLlama:
            return ChatTemplateTokens(
                beginSequence: nil,
                instructStart: nil,
                instructEnd: nil,
                endOfTurn: "</s>",
                systemHeader: "<|system|>\n",
                userHeader: "<|user|>\n",
                assistantHeader: "<|assistant|>\n"
            )
        case .qwen2:
            return ChatTemplateTokens(
                beginSequence: nil,
                instructStart: nil,
                instructEnd: nil,
                endOfTurn: "<|im_end|>\n",
                systemHeader: "<|im_start|>system\n",
                userHeader: "<|im_start|>user\n",
                assistantHeader: "<|im_start|>assistant\n"
            )
        case .mistral:
            return ChatTemplateTokens(
                beginSequence: "<s>",
                instructStart: "[INST]",
                instructEnd: "[/INST]",
                endOfTurn: nil,
                systemHeader: nil,
                userHeader: nil,
                assistantHeader: nil
            )
        case .phi:
            return ChatTemplateTokens(
                beginSequence: nil,
                instructStart: "Instruct: ",
                instructEnd: "\nOutput: ",
                endOfTurn: nil,
                systemHeader: nil,
                userHeader: nil,
                assistantHeader: nil
            )
        case .llama32:
            return ChatTemplateTokens(
                beginSequence: "<|begin_of_text|>",
                instructStart: nil,
                instructEnd: nil,
                endOfTurn: "<|eot_id|>",
                systemHeader: "<|start_header_id|>system<|end_header_id|>",
                userHeader: "<|start_header_id|>user<|end_header_id|>",
                assistantHeader: "<|start_header_id|>assistant<|end_header_id|>"
            )
        }
    }
}

/// Tokens used in chat templates
struct ChatTemplateTokens: Sendable {
    let beginSequence: String?
    let instructStart: String?
    let instructEnd: String?
    let endOfTurn: String?
    let systemHeader: String?
    let userHeader: String?
    let assistantHeader: String?
}

/// Configuration for an LLM model
public struct LLMModelConfiguration: Codable, Sendable {
    /// Unique identifier for the model
    let id: LLMModelID

    /// HuggingFace repository name
    let repository: String

    /// Model file name in the repository
    let fileName: String

    /// Generic local file name (e.g., "llm.gguf")
    let localFileName: String

    /// Expected file size in bytes
    let expectedFileSize: Int64

    /// File size tolerance (percentage) for validation
    let fileSizeTolerance: Double

    /// Chat template format
    let chatTemplate: ChatTemplateFormat

    /// Default max tokens for generation
    let defaultMaxTokens: Int

    /// Default temperature for generation
    let defaultTemperature: Double

    /// Recommended context window size
    let contextWindow: Int

    /// Model license type
    let license: String

    /// Is this model recommended for production use?
    let recommended: Bool

    // MARK: - Computed Properties

    /// Full download URL for the model
    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(repository)/resolve/main/\(fileName)")!
    }

    /// Minimum acceptable file size for validation
    var minimumFileSize: Int64 {
        Int64(Double(expectedFileSize) * (1.0 - fileSizeTolerance))
    }

    /// Maximum acceptable file size for validation
    var maximumFileSize: Int64 {
        Int64(Double(expectedFileSize) * (1.0 + fileSizeTolerance))
    }

    /// Human-readable file size
    public var fileSizeDescription: String {
        let gb = Double(expectedFileSize) / 1_000_000_000.0
        if gb >= 1.0 {
            return String(format: "%.1fGB", gb)
        } else {
            let mb = Double(expectedFileSize) / 1_000_000.0
            return String(format: "%.0fMB", mb)
        }
    }
}

/// Catalog of available LLM models optimized for query enhancement
public final class LLMModelCatalog: @unchecked Sendable {
    /// Shared catalog instance
    public static let shared = LLMModelCatalog()

    /// All available models
    private let models: [LLMModelID: LLMModelConfiguration]

    /// Default model to use if none specified - optimized for query enhancement (small size, good instruction following)
    public static let defaultModelID: LLMModelID = .llama32_1BInstruct

    private init() {
        // Initialize model catalog with models optimized for query enhancement
        self.models = [
            // Recommended models for query enhancement (prioritize smaller, instruction-tuned models)
            .llama32_1BInstruct: LLMModelConfiguration(
                id: .llama32_1BInstruct,
                repository: "bartowski/Llama-3.2-1B-Instruct-GGUF",
                fileName: "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
                localFileName: "llama-3.2-1b-instruct.gguf",
                expectedFileSize: 847_249_408, // ~808MB
                fileSizeTolerance: 0.05, // 5% tolerance
                chatTemplate: .llama32,
                defaultMaxTokens: 512,
                defaultTemperature: 0.7,
                contextWindow: 8192,
                license: "Meta Llama 3 Community License",
                recommended: true // Default - smallest recommended model, excellent for query enhancement
            ),
            .qwen25_15BInstruct: LLMModelConfiguration(
                id: .qwen25_15BInstruct,
                repository: "bartowski/Qwen2.5-1.5B-Instruct-GGUF",
                fileName: "Qwen2.5-1.5B-Instruct-Q4_K_M.gguf",
                localFileName: "qwen2.5-1.5b-instruct.gguf",
                expectedFileSize: 1_000_000_000, // ~954MB
                fileSizeTolerance: 0.05,
                chatTemplate: .qwen2,
                defaultMaxTokens: 512,
                defaultTemperature: 0.7,
                contextWindow: 32768,
                license: "Apache 2.0",
                recommended: true // Good balance of size and quality
            ),
            .phi3Mini4KInstruct: LLMModelConfiguration(
                id: .phi3Mini4KInstruct,
                repository: "bartowski/Phi-3-mini-4k-instruct-GGUF",
                fileName: "Phi-3-mini-4k-instruct-Q4_K_M.gguf",
                localFileName: "phi-3-mini-4k-instruct.gguf",
                expectedFileSize: 2_393_000_000, // ~2.23GB
                fileSizeTolerance: 0.05,
                chatTemplate: .phi,
                defaultMaxTokens: 512,
                defaultTemperature: 0.7,
                contextWindow: 4096,
                license: "MIT",
                recommended: true
            ),
            .qwen25_3BInstruct: LLMModelConfiguration(
                id: .qwen25_3BInstruct,
                repository: "bartowski/Qwen2.5-3B-Instruct-GGUF",
                fileName: "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
                localFileName: "qwen2.5-3b-instruct.gguf",
                expectedFileSize: 2_000_000_000, // ~1.9GB
                fileSizeTolerance: 0.05,
                chatTemplate: .qwen2,
                defaultMaxTokens: 512,
                defaultTemperature: 0.7,
                contextWindow: 32768,
                license: "Apache 2.0",
                recommended: true
            ),
            .ministral3BInstruct: LLMModelConfiguration(
                id: .ministral3BInstruct,
                repository: "bartowski/mistralai_Ministral-3-3B-Instruct-2512-GGUF",
                fileName: "mistralai_Ministral-3-3B-Instruct-2512-Q4_K_M.gguf",
                localFileName: "ministral-3-3b-instruct.gguf",
                expectedFileSize: 2_150_000_000, // ~2.15GB
                fileSizeTolerance: 0.05,
                chatTemplate: .mistral,
                defaultMaxTokens: 512,
                defaultTemperature: 0.7,
                contextWindow: 2048,
                license: "Apache 2.0",
                recommended: true
            ),
            
            // Legacy models
            .tinyLlama11BChat: LLMModelConfiguration(
                id: .tinyLlama11BChat,
                repository: "TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF",
                fileName: "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
                localFileName: "tinyllama-1.1b-chat-v1.0.gguf",
                expectedFileSize: 669_014_208, // ~638MB
                fileSizeTolerance: 0.05,
                chatTemplate: .tinyLlama,
                defaultMaxTokens: 512,
                defaultTemperature: 0.7,
                contextWindow: 2048,
                license: "Apache 2.0",
                recommended: false // Legacy - use Llama 3.2 1B instead
            ),
            .qwen215BInstruct: LLMModelConfiguration(
                id: .qwen215BInstruct,
                repository: "Qwen/Qwen2-1.5B-Instruct-GGUF",
                fileName: "qwen2-1_5b-instruct-q4_k_m.gguf",
                localFileName: "qwen2-1.5b-instruct.gguf",
                expectedFileSize: 986_045_824, // ~986MB
                fileSizeTolerance: 0.05,
                chatTemplate: .qwen2,
                defaultMaxTokens: 512,
                defaultTemperature: 0.7,
                contextWindow: 32768,
                license: "Apache 2.0",
                recommended: false // Legacy - use Qwen2.5 1.5B instead
            )
        ]
    }

    // MARK: - Public API

    /// Get model configuration by ID
    /// - Parameter id: Model identifier
    /// - Returns: Model configuration, or nil if not found
    public func model(for id: LLMModelID) -> LLMModelConfiguration? {
        return models[id]
    }

    /// Get default model configuration
    public var defaultModel: LLMModelConfiguration {
        return models[Self.defaultModelID]!
    }

    /// Get all available models
    var allModels: [LLMModelConfiguration] {
        return Array(models.values).sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// Get recommended models only
    var recommendedModels: [LLMModelConfiguration] {
        return allModels.filter { $0.recommended }
    }

    /// Validate file size against model configuration
    /// - Parameters:
    ///   - fileSize: Actual file size in bytes
    ///   - modelID: Model identifier
    /// - Returns: True if file size is within acceptable range
    public func validateFileSize(_ fileSize: Int64, for modelID: LLMModelID) -> Bool {
        guard let model = models[modelID] else { return false }
        return fileSize >= model.minimumFileSize && fileSize <= model.maximumFileSize
    }
}
