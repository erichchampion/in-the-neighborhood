import SwiftUI
import LLMIntegration

struct ModelDownloadView: View {
    @ObservedObject var downloadManager: LLMModelDownloadManager
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.blue)
                .accessibilityHidden(true)
            
            Text("Downloading AI Model")
                .font(.headline)
            
            Text("This may take several minutes on first launch")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            ProgressView(value: downloadManager.downloadProgress) {
                Text("\(Int(downloadManager.downloadProgress * 100))%")
                    .font(.caption)
            }
            .progressViewStyle(.linear)
            
            if let modelConfig = downloadManager.currentModelConfig {
                Text("\(modelConfig.fileSizeDescription)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.bordered)
        }
        .padding(30)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 10)
    }
}

