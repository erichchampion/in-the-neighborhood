import UIKit
import MetasearchCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {

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
