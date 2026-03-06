import Foundation
import SwiftData
import CoreLocation

/// A persisted local store the user has saved from search results.
@Model
public final class SavedStore {
    public var id: String
    public var name: String
    public var address: String?
    public var phone: String?
    public var latitude: Double
    public var longitude: Double
    public var notes: String?
    public var savedDate: Date
    public var categories: [String]

    public init(
        id: String = UUID().uuidString,
        name: String,
        address: String? = nil,
        phone: String? = nil,
        latitude: Double,
        longitude: Double,
        notes: String? = nil,
        savedDate: Date = .now,
        categories: [String] = []
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.phone = phone
        self.latitude = latitude
        self.longitude = longitude
        self.notes = notes
        self.savedDate = savedDate
        self.categories = categories
    }

    public var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
