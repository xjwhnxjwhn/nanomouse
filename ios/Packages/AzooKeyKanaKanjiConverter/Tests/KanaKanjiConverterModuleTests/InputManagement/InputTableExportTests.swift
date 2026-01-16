@testable import KanaKanjiConverterModule
internal import OrderedCollections
import XCTest

final class InputTableExportTests: XCTestCase {
    func testExportTable_EncodesCharactersAndTokens() throws {
        // Build a table with: "ka" -> "か",
        // "n" + any1 -> "ん" + any1,
        // "n" + composition-separator -> "ん",
        // "{" "}" -> "{" "}"
        let table = InputTable(baseMapping: [
            [.piece(.character("k")), .piece(.character("a"))]: [
                .character("か")
            ],
            [.piece(.character("n")), .any1]: [
                .character("ん"), .any1
            ],
            [.piece(.character("n")), .piece(.compositionSeparator)]: [
                .character("ん")
            ],
            [.piece(.character("{")), .piece(.character("}"))]: [
                .character("{"), .character("}")
            ]
        ])

        let tsv = try InputStyleManager.exportTable(table)
        let lines = Set(tsv.components(separatedBy: "\n"))

        // Expect braces to be tokenized, and any1/composition-separator encoded.
        let expected: Set<String> = [
            "ka\tか",
            "n{any character}\tん{any character}",
            "n{composition-separator}\tん",
            "{lbracket}{rbracket}\t{lbracket}{rbracket}"
        ]

        XCTAssertEqual(lines, expected)
    }

    func testExportTable_EncodesShiftKeys() throws {
        // key: "k" then Shift+0 → value: "X"
        // key: Shift+_ → value: "Y"
        let table = InputTable(baseMapping: [
            [.piece(.character("k")), .piece(.key(intention: "0", input: "0", modifiers: Set([.shift])))]: [
                .character("X")
            ],
            [.piece(.key(intention: "_", input: "_", modifiers: Set([.shift])))]: [
                .character("Y")
            ]
        ])

        let tsv = try InputStyleManager.exportTable(table)
        let lines = Set(tsv.components(separatedBy: "\n"))

        let expected: Set<String> = [
            "k{shift 0}\tX",
            "{shift _}\tY"
        ]
        XCTAssertEqual(lines, expected)
    }

    func testExportTable_ThrowsOnUnsupportedKey() {
        // Unsupported key: Shift+A (only Shift+0 and Shift+_ are supported)
        let table = InputTable(baseMapping: [
            [.piece(.key(intention: "A", input: "A", modifiers: Set([.shift])))]: [
                .character("Z")
            ]
        ])

        XCTAssertThrowsError(try InputStyleManager.exportTable(table)) { error in
            // Verify the error type is ExportError.unsupportedKeyElement
            guard case InputStyleManager.ExportError.unsupportedKeyElement = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }

    func testKeepingOriginalOrder() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("custom.tsv")
        try "a\tあ\nka\tか\n".write(to: url, atomically: true, encoding: .utf8)
        let table = try InputStyleManager.loadTable(from: url)
        let tsv = try InputStyleManager.exportTable(table)
        let expected = """
        a\tあ
        ka\tか
        """
        XCTAssertEqual(tsv, expected)
    }

    func testDefaultTableExport() throws {
        let table = InputTable.defaultRomanToKana
        let tsv = try InputStyleManager.exportTable(table)
        XCTAssertTrue(tsv.hasPrefix("a\tあ"))
    }
}
