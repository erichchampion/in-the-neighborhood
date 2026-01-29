import XCTest
@testable import MetasearchCore
import CoreLocation

final class SearchResultSummaryTests: XCTestCase {

    private func makeResult(
        id: String = "id",
        title: String = "Title",
        description: String? = "Description text",
        source: String = "web",
        url: URL? = URL(string: "https://example.com")
    ) -> SearchResult {
        SearchResult(
            id: id,
            title: title,
            description: description,
            source: source,
            sourceType: .online,
            url: url,
            location: nil,
            distance: nil,
            metadata: [:]
        )
    }

    func test_emptyArray_returnsEmptyString() {
        let result = SearchResultSummary.summarizeForAgent(results: [], maxItems: 8)
        XCTAssertTrue(result.isEmpty)
    }

    func test_nResults_producesUpToMaxItemsLines() {
        let results = (1...5).map { i in
            makeResult(id: "id-\(i)", title: "Title \(i)", description: "Desc \(i)", url: URL(string: "https://example.com/\(i)"))
        }
        let summary = SearchResultSummary.summarizeForAgent(results: results, maxItems: 8)
        let lines = summary.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 5)
        for (i, line) in lines.enumerated() {
            XCTAssertTrue(line.contains("Title \(i + 1)"))
            XCTAssertTrue(line.contains("example.com"))
        }
    }

    func test_maxItems_capsNumberOfLines() {
        let results = (1...10).map { i in
            makeResult(id: "id-\(i)", title: "Title \(i)", description: "Desc \(i)")
        }
        let summary = SearchResultSummary.summarizeForAgent(results: results, maxItems: 3)
        let lines = summary.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)
    }

    func test_resultWithNilDescription_stillProducesOneLine() {
        let results = [
            makeResult(id: "1", title: "Only Title", description: nil, url: URL(string: "https://site.com"))
        ]
        let summary = SearchResultSummary.summarizeForAgent(results: results, maxItems: 8)
        let lines = summary.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("Only Title"))
        XCTAssertTrue(lines[0].contains("site.com"))
    }
}
