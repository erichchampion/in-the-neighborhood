import XCTest
@preconcurrency import NaturalLanguage
@testable import MetasearchCore

final class QueryClassifierTests: XCTestCase {

    private var classifier: QueryClassifier!

    override func setUpWithError() throws {
        try XCTSkipIf(
            NLEmbedding.wordEmbedding(for: .english) == nil,
            "English word embedding unavailable in this test environment"
        )
        classifier = QueryClassifier()
    }

    // MARK: - tokenize

    func test_tokenize_lowersAndStripsPunctuation() {
        XCTAssertEqual(
            QueryClassifier.tokenize("Wireless Bluetooth Headphones!"),
            ["wireless", "bluetooth", "headphones"]
        )
    }

    func test_tokenize_dropsShortAndStopwords() {
        XCTAssertEqual(QueryClassifier.tokenize("a book for the kids"), ["book", "kids"])
    }

    func test_tokenize_emptyOrWhitespace() {
        XCTAssertEqual(QueryClassifier.tokenize(""), [])
        XCTAssertEqual(QueryClassifier.tokenize("   "), [])
    }

    // MARK: - classify (positive cases)

    func test_classify_electronicsQuery() {
        XCTAssertEqual(classifier.classify("wireless headphones"), .electronics)
    }

    func test_classify_personalCareQuery() {
        XCTAssertEqual(classifier.classify("shampoo"), .personalCare)
    }

    func test_classify_hardwareQuery() {
        XCTAssertEqual(classifier.classify("drill bit"), .hardware)
    }

    func test_classify_groceryQuery() {
        XCTAssertEqual(classifier.classify("bread"), .grocery)
    }

    func test_classify_clothingQuery() {
        XCTAssertEqual(classifier.classify("denim jacket"), .clothing)
    }

    func test_classify_mediaQuery() {
        XCTAssertEqual(classifier.classify("vinyl record"), .media)
    }

    func test_classify_petFoodQuery() {
        XCTAssertEqual(classifier.classify("dog food"), .petFood)
    }

    // MARK: - classify (rejection cases)

    func test_classify_gibberishReturnsNil() {
        XCTAssertNil(classifier.classify("asdfqwerty"))
    }

    func test_classify_emptyReturnsNil() {
        XCTAssertNil(classifier.classify(""))
        XCTAssertNil(classifier.classify("   "))
    }

    func test_classify_lowercaseBookTitleNotMisclassified() {
        // "On Tyranny" may classify as .book or nil (depending on whether
        // the title words embed near book seeds). What matters is it does
        // NOT get misclassified into a non-book category that would skip
        // OpenLibrary.
        let result = classifier.classify("on tyranny")
        XCTAssert(
            result == nil || result == .book,
            "Expected nil or .book, got \(String(describing: result))"
        )
    }
}
