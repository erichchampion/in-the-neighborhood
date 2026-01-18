import SwiftUI
import MetasearchCore

public struct ResultsView: View {
    let results: [SearchResult]
    
    public init(results: [SearchResult]) {
        self.results = results
    }
    
    private var amazonResults: [SearchResult] {
        results.filter { $0.source == "amazon" }
    }
    
    private var otherResults: [SearchResult] {
        results.filter { $0.source != "amazon" }
    }
    
    public var body: some View {
        List {
            // Amazon Products Section
            if !amazonResults.isEmpty {
                Section {
                    ForEach(amazonResults) { result in
                        AmazonProductCard(result: result)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("Amazon Products")
                        .font(.headline)
                        .textCase(nil)
                }
            }
            
            // Other Results Section
            if !otherResults.isEmpty {
                Section {
                    ForEach(otherResults) { result in
                        ResultRowView(result: result)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                } header: {
                    if !amazonResults.isEmpty {
                        Text("Other Results")
                            .font(.headline)
                            .textCase(nil)
                    }
                }
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
