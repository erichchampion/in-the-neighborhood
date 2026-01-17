import Foundation

/// Helper for accessing bundle resources
enum BundleHelper {
    /// Get path for a resource in the bundle
    /// - Parameters:
    ///   - name: Resource name (without extension)
    ///   - type: Resource type/extension
    /// - Returns: Path to resource, or nil if not found
    static func path(forResource name: String, ofType type: String) -> String? {
        return Bundle.main.path(forResource: name, ofType: type)
    }
}
