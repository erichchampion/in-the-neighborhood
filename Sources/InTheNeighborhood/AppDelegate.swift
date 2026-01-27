import UIKit
import LLMIntegration
import MetasearchCore

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
        
        // Trigger ad domain list download if not available
        Task {
            if !AdDomainListDownloadManager.shared.isListAvailable() {
                LoggingService.shared.info(
                    "Ad domain list not available, starting download",
                    category: "AppDelegate"
                )
                try? await AdDomainListDownloadManager.shared.startDownloadIfNeeded()
            } else {
                LoggingService.shared.info(
                    "Ad domain list already available",
                    category: "AppDelegate"
                )
            }
        }
        
        return true
    }
}
