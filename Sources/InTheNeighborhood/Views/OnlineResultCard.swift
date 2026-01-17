import SwiftUI
import MetasearchCore

struct OnlineResultCard: View {
    let result: SearchResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.headline)
                    
                    if let description = result.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Text(sourceLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let url = result.url {
                    Button(action: {
                        UIApplication.shared.open(url)
                    }) {
                        Label("Open", systemImage: "arrow.up.right.square")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private var sourceLabel: String {
        switch result.sourceType {
        case .local:
            return "Local"
        case .regional:
            return "Regional / Ethical Online"
        case .online:
            return "Online Option"
        }
    }
}
