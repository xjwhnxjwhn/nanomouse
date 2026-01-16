@testable import KanaKanjiConverterModule
@testable import KanaKanjiConverterModuleWithDefaultDictionary
import XCTest

final class TextReplacerTests: XCTestCase {
    func testEmojiTextReplacer() throws {
        let textReplacer = TextReplacer.withDefaultEmojiDictionary()
        XCTAssertFalse(textReplacer.isEmpty)
        do {
            let searchResult = textReplacer.getSearchResult(query: "カニ", target: [.emoji])
            XCTAssertEqual(searchResult.count, 1)
            XCTAssertEqual(searchResult[0], .init(query: "かに", text: "🦀️"))
        }
        if #available(iOS 18.4, macOS 15.3, *) {
            let searchResult = textReplacer.getSearchResult(query: "テツヤ", target: [.emoji])
            XCTAssertEqual(searchResult.count, 1)
            XCTAssertEqual(searchResult[0], .init(query: "てつや", text: "🫩️"))
        }
    }
}
