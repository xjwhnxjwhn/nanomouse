@testable import KanaKanjiConverterModule
internal import OrderedCollections
import XCTest

final class KeyInputTests: XCTestCase {
    func testKeySpecificRuleBeatsCharacterRule() throws {
        let table = InputTable(baseMapping: [
            [.piece(.key(intention: "0", input: "0", modifiers: [.shift]))]: [.character("あ")],
            [.piece(.character("0"))]: [.character("い")]
        ])

        XCTAssertEqual(table.applied(currentText: [], added: .key(intention: "0", input: "0", modifiers: [.shift])), Array("あ"))
        XCTAssertEqual(table.applied(currentText: [], added: .character("0")), Array("い"))
    }

    func testKeyRuleOnly() throws {
        // {shift 0} のみがある場合、.key は一致、.character は素通り
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("custom_key_only.tsv")
        try "{shift 0}\tA".write(to: url, atomically: true, encoding: .utf8)

        let table = InputTable(baseMapping: [
            [.piece(.key(intention: "0", input: "0", modifiers: [.shift]))]: [.character("A")]
        ])

        XCTAssertEqual(table.applied(currentText: [], added: .key(intention: "0", input: "0", modifiers: [.shift])), Array("A"))
        XCTAssertEqual(table.applied(currentText: [], added: .character("0")), Array("0"))
    }

    func testCharacterRuleOnly() throws {
        // 0 のみがある場合、.key も .character も一致
        let table = InputTable(baseMapping: [
            [.piece(.character("0"))]: [.character("Z")]
        ])
        XCTAssertEqual(table.applied(currentText: [], added: .key(intention: "0", input: "0", modifiers: [.shift])), Array("Z"))
        XCTAssertEqual(table.applied(currentText: [], added: .character("0")), Array("Z"))
    }

    func testShiftUnderscorePriority() throws {
        // {shift _} と _ の両方がある場合の優先
        let table = InputTable(baseMapping: [
            [.piece(.key(intention: "_", input: "_", modifiers: [.shift ]))]: [.character("X")],
            [.piece(.character("_"))]: [.character("Y")]
        ])
        XCTAssertEqual(table.applied(currentText: [], added: .key(intention: "_", input: "_", modifiers: [.shift])), Array("X"))
        XCTAssertEqual(table.applied(currentText: [], added: .character("_")), Array("Y"))
    }

    func testAnyCharacterCapturesKeyIntention() throws {
        // {any character} は .key(intention: c) にも一致し、c を代入できる
        let table = InputTable(baseMapping: [
            [.piece(.character("n")), .any1]: [.character("ん"), .any1]
        ])
        XCTAssertEqual(table.applied(currentText: ["n"], added: .key(intention: "a", input: "a", modifiers: [.shift])), Array("んa"))
    }

    func testKeyAtTailMatches() throws {
        let table = InputTable(baseMapping: [
            [.piece(.character("k")), .piece(.key(intention: "0", input: "0", modifiers: [.shift]))]: [.character("か")]
        ])

        // buffer に 'k' があり、追加入力が .key(intention: "0", [.shift]) の場合に一致
        XCTAssertEqual(table.applied(currentText: ["k"], added: .key(intention: "0", input: "0", modifiers: [.shift])), Array("か"))

        // 単なる文字 '0' では一致せず、素通り
        XCTAssertEqual(table.applied(currentText: ["k"], added: .character("0")), Array("k0"))
    }

    func testKeyAtTailPriorityOverCharacter() throws {
        // k{shift 0} と k0 の両方があり、.key を優先
        let table = InputTable(baseMapping: [
            [.piece(.character("k")), .piece(.key(intention: "0", input: "0", modifiers: [.shift]))]: [.character("か")],
            [.piece(.character("k")), .piece(.character("0"))]: [.character("こ")]
        ])

        // .key は k{shift 0} に一致
        XCTAssertEqual(table.applied(currentText: ["k"], added: .key(intention: "0", input: "0", modifiers: [.shift])), Array("か"))
        // 文字 '0' は k0 に一致
        XCTAssertEqual(table.applied(currentText: ["k"], added: .character("0")), Array("こ"))
    }

    func testComposingTextWithKey() throws {
        // ComposingText 上でも .key 入力が適用されること
        let table = InputTable(baseMapping: [
            [.piece(.key(intention: "0", input: "0", modifiers: [.shift]))]: [.character("が")],
            [.piece(.character("0"))]: [.character("お")]
        ])
        InputStyleManager.registerInputStyle(table: table, for: "0-or-shift-0-285913")
        var c = ComposingText()
        // カスタムテーブルに対して .key を1要素入力
        c.insertAtCursorPosition([
            .init(piece: .key(intention: "0", input: "0", modifiers: [.shift]), inputStyle: .mapped(id: .tableName("0-or-shift-0-285913")))
        ])
        XCTAssertEqual(c.convertTarget, "が")

        // 文字としての "0" は文字変換側に一致
        c.insertAtCursorPosition("0", inputStyle: .mapped(id: .tableName("0-or-shift-0-285913")))
        XCTAssertEqual(c.convertTarget, "がお")
    }
}
