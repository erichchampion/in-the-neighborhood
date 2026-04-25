import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
@Generable
#endif
public enum ProductCondition: String, Equatable, Hashable, Codable, Sendable {
    case new
    case used
    case refurbished
}
