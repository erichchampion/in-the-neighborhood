import XCTest
@testable import MetasearchCore

final class DenyListFilterTests: XCTestCase {
    
    func test_DenyListFilter_FiltersDomains() throws {
        let filter = DenyListFilter(defaultDomains: ["amazon.com", "walmart.com", "target.com"])
        
        let amazonURL = try XCTUnwrap(URL(string: "https://www.amazon.com/product"))
        let walmartURL = try XCTUnwrap(URL(string: "https://walmart.com/item"))
        let targetURL = try XCTUnwrap(URL(string: "https://target.com/product"))
        let allowedURL = try XCTUnwrap(URL(string: "https://localstore.com/product"))
        
        XCTAssertTrue(filter.shouldFilter(url: amazonURL))
        XCTAssertTrue(filter.shouldFilter(url: walmartURL))
        XCTAssertTrue(filter.shouldFilter(url: targetURL))
        XCTAssertFalse(filter.shouldFilter(url: allowedURL))
    }
    
    func test_DenyListFilter_CaseInsensitive() throws {
        let filter = DenyListFilter(defaultDomains: ["amazon.com"])
        
        let url1 = try XCTUnwrap(URL(string: "https://AMAZON.COM/product"))
        let url2 = try XCTUnwrap(URL(string: "https://Amazon.com/item"))
        
        XCTAssertTrue(filter.shouldFilter(url: url1))
        XCTAssertTrue(filter.shouldFilter(url: url2))
    }
    
    func test_DenyListFilter_SubdomainMatching() throws {
        let filter = DenyListFilter(defaultDomains: ["amazon.com"])
        
        let url1 = try XCTUnwrap(URL(string: "https://www.amazon.com/product"))
        let url2 = try XCTUnwrap(URL(string: "https://smile.amazon.com/item"))
        
        XCTAssertTrue(filter.shouldFilter(url: url1))
        XCTAssertTrue(filter.shouldFilter(url: url2))
    }
    
    func test_DenyListFilter_AddDomain() throws {
        var filter = DenyListFilter(defaultDomains: ["amazon.com"])
        
        let url = try XCTUnwrap(URL(string: "https://example.com/product"))
        XCTAssertFalse(filter.shouldFilter(url: url))
        
        filter.addDomain("example.com")
        XCTAssertTrue(filter.shouldFilter(url: url))
    }
    
    func test_DenyListFilter_RemoveDomain() throws {
        var filter = DenyListFilter(defaultDomains: ["amazon.com"])
        
        let url = try XCTUnwrap(URL(string: "https://amazon.com/product"))
        XCTAssertTrue(filter.shouldFilter(url: url))
        
        filter.removeDomain("amazon.com")
        XCTAssertFalse(filter.shouldFilter(url: url))
    }
    
    func test_DenyListFilter_DifferentTLDs() throws {
        let filter = DenyListFilter(defaultDomains: ["amazon.com"])
        
        // Should filter amazon.com and all variants
        let url1 = try XCTUnwrap(URL(string: "https://amazon.com/product"))
        let url2 = try XCTUnwrap(URL(string: "https://amazon.ca/product"))
        let url3 = try XCTUnwrap(URL(string: "https://www.amazon.ca/product"))
        let url4 = try XCTUnwrap(URL(string: "https://amazon.co.uk/product"))
        let url5 = try XCTUnwrap(URL(string: "https://smile.amazon.ca/product"))
        
        XCTAssertTrue(filter.shouldFilter(url: url1), "amazon.com should be filtered")
        XCTAssertTrue(filter.shouldFilter(url: url2), "amazon.ca should be filtered when amazon.com is denied")
        XCTAssertTrue(filter.shouldFilter(url: url3), "www.amazon.ca should be filtered when amazon.com is denied")
        XCTAssertTrue(filter.shouldFilter(url: url4), "amazon.co.uk should be filtered when amazon.com is denied")
        XCTAssertTrue(filter.shouldFilter(url: url5), "smile.amazon.ca should be filtered when amazon.com is denied")
        
        // Other domains should not be filtered
        let allowedURL = try XCTUnwrap(URL(string: "https://localstore.com/product"))
        XCTAssertFalse(filter.shouldFilter(url: allowedURL), "Other domains should not be filtered")
    }
}
