import XCTest
import CoreLocation
@testable import MetasearchCore

final class NearDuplicateMergerTests: XCTestCase {

    // MARK: - normalizedTitle

    func test_normalizedTitle_stripsPunctuationAndLowercases() {
        XCTAssertEqual(NearDuplicateMerger.normalizedTitle("Joe's Bike Shop!"), "joes bike shop")
    }

    func test_normalizedTitle_dropsSuffixWords() {
        XCTAssertEqual(NearDuplicateMerger.normalizedTitle("Acme Hardware, Inc."), "acme hardware")
        XCTAssertEqual(NearDuplicateMerger.normalizedTitle("The Coffee Co."), "coffee")
        XCTAssertEqual(NearDuplicateMerger.normalizedTitle("Foo LLC"), "foo")
    }

    // MARK: - titlesMatch

    func test_titlesMatch_substringAfterNormalization() {
        XCTAssertTrue(NearDuplicateMerger.titlesMatch("Joe's Bike Shop", "Joe's Bikes"))
    }

    func test_titlesMatch_rejectsDifferentLocations() {
        XCTAssertFalse(NearDuplicateMerger.titlesMatch("Trek Bicycle Bellevue", "Trek Bicycle Seattle"))
    }

    // MARK: - sourcePriority

    func test_sourcePriority_mapkitBeatsOverpassBeatsNominatim() {
        XCTAssertLessThan(
            NearDuplicateMerger.sourcePriority(SourceIdentifier.mapkit),
            NearDuplicateMerger.sourcePriority(SourceIdentifier.overpass)
        )
        XCTAssertLessThan(
            NearDuplicateMerger.sourcePriority(SourceIdentifier.overpass),
            NearDuplicateMerger.sourcePriority("nominatim")
        )
    }

    // MARK: - merge

    func test_merge_collapsesMatchingLocalsAcrossSources() {
        let loc = CLLocation(latitude: 47.6062, longitude: -122.3321)
        let nearby = CLLocation(latitude: 47.60625, longitude: -122.33215) // ~6m away
        let mapkit = makeLocal(id: "mapkit-1", title: "Joe's Bike Shop", source: SourceIdentifier.mapkit, location: loc)
        let overpass = makeLocal(id: "overpass-1", title: "Joe's Bikes", source: SourceIdentifier.overpass, location: nearby)

        let merged = NearDuplicateMerger.merge([mapkit, overpass])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.id, "mapkit-1")
        let sources = merged.first?.metadata["merged_sources"] as? [String]
        XCTAssertEqual(sources?.sorted(), [SourceIdentifier.mapkit, SourceIdentifier.overpass].sorted())
    }

    func test_merge_keepsBothWhenTooFarApart() {
        let loc1 = CLLocation(latitude: 47.6062, longitude: -122.3321)
        let loc2 = CLLocation(latitude: 47.6080, longitude: -122.3321) // ~200m
        let mapkit = makeLocal(id: "mapkit-1", title: "Joe's Bike Shop", source: SourceIdentifier.mapkit, location: loc1)
        let overpass = makeLocal(id: "overpass-1", title: "Joe's Bikes", source: SourceIdentifier.overpass, location: loc2)

        let merged = NearDuplicateMerger.merge([mapkit, overpass])

        XCTAssertEqual(merged.count, 2)
    }

    func test_merge_keepsBothWhenTitlesDontMatch() {
        let loc = CLLocation(latitude: 47.6062, longitude: -122.3321)
        let mapkit = makeLocal(id: "mapkit-1", title: "Joe's Bike Shop", source: SourceIdentifier.mapkit, location: loc)
        let overpass = makeLocal(id: "overpass-1", title: "Acme Hardware", source: SourceIdentifier.overpass, location: loc)

        let merged = NearDuplicateMerger.merge([mapkit, overpass])

        XCTAssertEqual(merged.count, 2)
    }

    func test_merge_threeSourcesCollapseToOneWithMergedSourcesList() {
        let loc = CLLocation(latitude: 47.6062, longitude: -122.3321)
        let mapkit = makeLocal(id: "mapkit-1", title: "Joe's Bike Shop", source: SourceIdentifier.mapkit, location: loc)
        let overpass = makeLocal(id: "overpass-1", title: "Joe's Bikes", source: SourceIdentifier.overpass, location: loc)
        let nominatim = makeLocal(id: "nominatim-1", title: "Joe's Bike", source: "nominatim", location: loc)

        let merged = NearDuplicateMerger.merge([mapkit, overpass, nominatim])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.id, "mapkit-1")
        let sources = merged.first?.metadata["merged_sources"] as? [String] ?? []
        XCTAssertEqual(Set(sources), [SourceIdentifier.mapkit, SourceIdentifier.overpass, "nominatim"])
    }

    func test_merge_carriesOverpassCategoryTagOntoMapKitPrimary() {
        let loc = CLLocation(latitude: 47.6062, longitude: -122.3321)
        let mapkit = makeLocal(id: "mapkit-1", title: "Joe's Bike Shop", source: SourceIdentifier.mapkit, location: loc, metadata: [:])
        let overpass = makeLocal(
            id: "overpass-1",
            title: "Joe's Bikes",
            source: SourceIdentifier.overpass,
            location: loc,
            metadata: ["category_tag": "repair" as AnyHashable]
        )

        let merged = NearDuplicateMerger.merge([mapkit, overpass])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.metadata["category_tag"] as? String, "repair")
    }

    func test_merge_primaryMetadataWinsOnConflict() {
        let loc = CLLocation(latitude: 47.6062, longitude: -122.3321)
        let mapkit = makeLocal(
            id: "mapkit-1",
            title: "Joe's Bike Shop",
            source: SourceIdentifier.mapkit,
            location: loc,
            metadata: ["category_tag": "shop" as AnyHashable]
        )
        let overpass = makeLocal(
            id: "overpass-1",
            title: "Joe's Bikes",
            source: SourceIdentifier.overpass,
            location: loc,
            metadata: ["category_tag": "repair" as AnyHashable]
        )

        let merged = NearDuplicateMerger.merge([mapkit, overpass])

        XCTAssertEqual(merged.first?.metadata["category_tag"] as? String, "shop")
    }

    func test_merge_passesNonLocalsThrough() {
        let loc = CLLocation(latitude: 47.6062, longitude: -122.3321)
        let mapkit = makeLocal(id: "mapkit-1", title: "Joe's Bike Shop", source: SourceIdentifier.mapkit, location: loc)
        let onlineProduct = SearchResult(
            id: "amz-1",
            title: "Joe's Bike Shop",
            description: nil,
            source: SourceIdentifier.amazon,
            sourceType: .online,
            category: .product,
            url: URL(string: "https://example.com"),
            location: nil,
            distance: nil,
            metadata: [:]
        )

        let merged = NearDuplicateMerger.merge([mapkit, onlineProduct])

        XCTAssertEqual(merged.count, 2)
    }

    func test_merge_emptyInput() {
        XCTAssertEqual(NearDuplicateMerger.merge([]).count, 0)
    }

    func test_merge_preservesOriginalOrder() {
        let loc = CLLocation(latitude: 47.6062, longitude: -122.3321)
        let other = makeLocal(id: "mapkit-other", title: "Acme Hardware", source: SourceIdentifier.mapkit, location: loc)
        let mapkit = makeLocal(id: "mapkit-1", title: "Joe's Bike Shop", source: SourceIdentifier.mapkit, location: loc)
        let overpass = makeLocal(id: "overpass-1", title: "Joe's Bikes", source: SourceIdentifier.overpass, location: loc)

        let merged = NearDuplicateMerger.merge([other, mapkit, overpass])

        XCTAssertEqual(merged.map { $0.id }, ["mapkit-other", "mapkit-1"])
    }

    // MARK: - Helpers

    private func makeLocal(
        id: String,
        title: String,
        source: String,
        location: CLLocation,
        metadata: [String: AnyHashable] = [:]
    ) -> SearchResult {
        SearchResult(
            id: id,
            title: title,
            description: nil,
            source: source,
            sourceType: .local,
            category: .local,
            url: nil,
            location: location,
            distance: 0,
            metadata: metadata
        )
    }
}
