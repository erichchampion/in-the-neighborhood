import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public actor RelevanceScorer {
    public init() {}
    
    public func scoreResult(_ result: SearchResult, query: String) async throws -> Double {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await scoreWithFoundationModel(result, query: query)
        }
        #endif
        return fallbackScore(result, query: query)
    }
    
    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func scoreWithFoundationModel(_ result: SearchResult, query: String) async throws -> Double {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            return fallbackScore(result, query: query)
        }
        
        let prompt = """
        Rate the relevance of this search result to the user's query on a scale of 0.0 to 1.0, where 0.0 is completely irrelevant and 1.0 is a perfect match.
        
        User Query: "\(query)"
        
        Result Title: "\(result.title)"
        Result Description: "\(result.description ?? "None")"
        
        Return ONLY a single floating point number between 0.0 and 1.0, nothing else.
        """
        
        do {
            let session = LanguageModelSession(model: model)
            let response = try await session.respond(to: prompt)
            let scoreString = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if let score = Double(scoreString), (0.0...1.0).contains(score) {
                return score
            }
            return fallbackScore(result, query: query)
        } catch {
            return fallbackScore(result, query: query)
        }
    }
    #endif
    
    private func fallbackScore(_ result: SearchResult, query: String) -> Double {
        let queryTerms = query.lowercased().split(separator: " ").map { String($0) }
        let titleLower = result.title.lowercased()
        let descLower = (result.description ?? "").lowercased()
        
        var matchCount = 0
        for term in queryTerms {
            if titleLower.contains(term) {
                matchCount += 2 // Title matches are worth more
            }
            if descLower.contains(term) {
                matchCount += 1
            }
        }
        
        let maxPossible = queryTerms.count * 3
        guard maxPossible > 0 else { return 0.5 }
        return min(1.0, Double(matchCount) / Double(maxPossible))
    }
}
