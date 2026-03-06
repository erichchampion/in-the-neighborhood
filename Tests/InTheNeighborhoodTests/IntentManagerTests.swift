import XCTest
@testable import InTheNeighborhood

final class IntentManagerTests: XCTestCase {

    nonisolated override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            IntentManager.shared.clearPendingSearch()
        }
    }

    nonisolated override func tearDown() {
        MainActor.assumeIsolated {
            IntentManager.shared.clearPendingSearch()
        }
        super.tearDown()
    }

    func testHandleLocalStoreIntent() {
        // Given
        let query = "Bookstore"
        
        // When
        MainActor.assumeIsolated {
            IntentManager.shared.handleSearchIntent(query: query, type: .localStores)
        }
        
        // Then
        MainActor.assumeIsolated {
            XCTAssertNotNil(IntentManager.shared.pendingSearch)
            XCTAssertEqual(IntentManager.shared.pendingSearch?.query, query)
            XCTAssertEqual(IntentManager.shared.pendingSearch?.type, .localStores)
        }
    }

    func testHandleProductIntent() {
        // Given
        let query = "Coffee Maker"
        
        // When
        MainActor.assumeIsolated {
            IntentManager.shared.handleSearchIntent(query: query, type: .products)
        }
        
        // Then
        MainActor.assumeIsolated {
            XCTAssertNotNil(IntentManager.shared.pendingSearch)
            XCTAssertEqual(IntentManager.shared.pendingSearch?.query, query)
            XCTAssertEqual(IntentManager.shared.pendingSearch?.type, .products)
        }
    }

    func testClearPendingSearch() {
        // Given
        MainActor.assumeIsolated {
            IntentManager.shared.handleSearchIntent(query: "Test", type: .general)
            XCTAssertNotNil(IntentManager.shared.pendingSearch)
        }
        
        // When
        MainActor.assumeIsolated {
            IntentManager.shared.clearPendingSearch()
        }
        
        // Then
        MainActor.assumeIsolated {
            XCTAssertNil(IntentManager.shared.pendingSearch)
        }
    }
}
