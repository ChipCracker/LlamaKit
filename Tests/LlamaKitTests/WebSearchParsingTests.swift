import XCTest
@testable import LlamaKitTools

final class WebSearchParsingTests: XCTestCase {
    private func loadFixture() throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ddg-lite-sample", withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParsesRealResultsAndFiltersAds() throws {
        let html = try loadFixture()
        let results = WebSearch.parse(html, maxResults: 5)

        // The sponsored (y.js / ad_provider / ad_domain) entry is filtered out.
        XCTAssertEqual(results.count, 2)

        // First real result: entity unescaped, redirect unwrapped.
        XCTAssertEqual(results[0].title, "Eiffelturm & Wikipedia")
        XCTAssertEqual(results[0].url, "https://de.wikipedia.org/wiki/Eiffelturm")
        XCTAssertTrue(results[0].snippet.contains("330 Meter"))

        // Second real result.
        XCTAssertEqual(results[1].url, "https://www.toureiffel.paris/de/monument/zahlen")
    }

    func testMaxResultsHonoured() throws {
        let html = try loadFixture()
        XCTAssertEqual(WebSearch.parse(html, maxResults: 1).count, 1)
    }
}
