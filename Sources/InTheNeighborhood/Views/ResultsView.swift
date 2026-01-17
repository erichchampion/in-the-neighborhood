import SwiftUI
import MetasearchCore

public struct ResultsView: View {
    let results: [SearchResult]
    
    public init(results: [SearchResult]) {
        self.results = results
    }
    
    public var body: some View {
        List {
            ForEach(results) { result in
                ResultRowView(result: result)
            }
        }
        .listStyle(.plain)
    }
}

struct ResultRowView: View {
    let result: SearchResult
    
    var body: some View {
        Group {
            switch result.sourceType {
            case .local:
                LocalBusinessCard(result: result)
            case .regional, .online:
                OnlineResultCard(result: result)
            }
        }
        .padding(.vertical, 4)
    }
}
