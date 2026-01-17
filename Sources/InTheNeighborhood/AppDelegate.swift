import UIKit
import LLMIntegration

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Trigger LLM model download if not available
        Task {
            if !LLMModelDownloadManager.shared.isModelAvailable() {
                LoggingService.shared.info(
                    "LLM model not available, starting download",
                    category: "AppDelegate"
                )
                try? await LLMModelDownloadManager.shared.startDownloadIfNeeded()
            } else {
                LoggingService.shared.info(
                    "LLM model already available",
                    category: "AppDelegate"
                )
            }
        }
        return true
    }
}
