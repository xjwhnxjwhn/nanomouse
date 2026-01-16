//
//  ComposingTextTests.swift
//  KanaKanjiConverterModuleTests
//
//  Created by ensan on 2022/12/18.
//  Copyright © 2022 ensan. All rights reserved.
//

@testable import KanaKanjiConverterModule
internal import OrderedCollections
import XCTest

final class ComposingTextTests: XCTestCase {
    func sequentialInput(_ composingText: inout ComposingText, sequence: String, inputStyle: InputStyle) {
        for char in sequence {
            composingText.insertAtCursorPosition(String(char), inputStyle: inputStyle)
        }
    }

    func testIsEmpty() throws {
        var c = ComposingText()
        XCTAssertTrue(c.isEmpty)
        c.insertAtCursorPosition("あ", inputStyle: .direct)
        XCTAssertFalse(c.isEmpty)
        c.stopComposition()
        XCTAssertTrue(c.isEmpty)
    }

    func testInsertAtCursorPosition() throws {
        // ダイレクト
        do {
            var c = ComposingText()
            c.insertAtCursorPosition("あ", inputStyle: .direct)
            XCTAssertEqual(c.input, [ComposingText.InputElement(character: "あ", inputStyle: .direct)])
            XCTAssertEqual(c.convertTarget, "あ")
            XCTAssertEqual(c.convertTargetCursorPosition, 1)

            c.insertAtCursorPosition("ん", inputStyle: .direct)
            XCTAssertEqual(c, ComposingText(convertTargetCursorPosition: 2, input: [.init(character: "あ", inputStyle: .direct), .init(character: "ん", inputStyle: .direct)], convertTarget: "あん"))
        }
        // ローマ字
        do {
            let inputStyle = InputStyle.roman2kana
            var c = ComposingText()
            c.insertAtCursorPosition("a", inputStyle: inputStyle)
            XCTAssertEqual(c.input, [ComposingText.InputElement(character: "a", inputStyle: inputStyle)])
            XCTAssertEqual(c.convertTarget, "あ")
            XCTAssertEqual(c.convertTargetCursorPosition, 1)

            c.insertAtCursorPosition("k", inputStyle: inputStyle)
            XCTAssertEqual(c, ComposingText(convertTargetCursorPosition: 2, input: [.init(character: "a", inputStyle: inputStyle), .init(character: "k", inputStyle: inputStyle)], convertTarget: "あk"))

            c.insertAtCursorPosition("i", inputStyle: inputStyle)
            XCTAssertEqual(c, ComposingText(convertTargetCursorPosition: 2, input: [.init(character: "a", inputStyle: inputStyle), .init(character: "k", inputStyle: inputStyle), .init(character: "i", inputStyle: inputStyle)], convertTarget: "あき"))
        }
        // ローマ字で一気に入力
        do {
            let inputStyle = InputStyle.roman2kana
            var c = ComposingText()
            c.insertAtCursorPosition("akafa", inputStyle: inputStyle)
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "a", inputStyle: inputStyle),
                ComposingText.InputElement(character: "k", inputStyle: inputStyle),
                ComposingText.InputElement(character: "a", inputStyle: inputStyle),
                ComposingText.InputElement(character: "f", inputStyle: inputStyle),
                ComposingText.InputElement(character: "a", inputStyle: inputStyle)
            ])
            XCTAssertEqual(c.convertTarget, "あかふぁ")
            XCTAssertEqual(c.convertTargetCursorPosition, 4)
        }
        // ローマ字の特殊ケース(促音)
        do {
            var c = ComposingText()
            sequentialInput(&c, sequence: "itte", inputStyle: .roman2kana)
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "i", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "t", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "t", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "e", inputStyle: .roman2kana)
            ])
            XCTAssertEqual(c.convertTarget, "いって")
            XCTAssertEqual(c.convertTargetCursorPosition, 3)
        }
        // ローマ字の特殊ケース(撥音)
        do {
            var c = ComposingText()
            sequentialInput(&c, sequence: "anta", inputStyle: .roman2kana)
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "a", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "n", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "t", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "a", inputStyle: .roman2kana)
            ])
            XCTAssertEqual(c.convertTarget, "あんた")
            XCTAssertEqual(c.convertTargetCursorPosition, 3)
        }
        // ミックス
        do {
            var c = ComposingText()
            c.insertAtCursorPosition("a", inputStyle: .direct)
            XCTAssertEqual(c.input, [ComposingText.InputElement(character: "a", inputStyle: .direct)])
            XCTAssertEqual(c.convertTarget, "a")
            XCTAssertEqual(c.convertTargetCursorPosition, 1)

            c.insertAtCursorPosition("k", inputStyle: .roman2kana)
            XCTAssertEqual(c, ComposingText(convertTargetCursorPosition: 2, input: [.init(character: "a", inputStyle: .direct), .init(character: "k", inputStyle: .roman2kana)], convertTarget: "ak"))

            c.insertAtCursorPosition("i", inputStyle: .roman2kana)
            XCTAssertEqual(c, ComposingText(convertTargetCursorPosition: 2, input: [.init(character: "a", inputStyle: .direct), .init(character: "k", inputStyle: .roman2kana), .init(character: "i", inputStyle: .roman2kana)], convertTarget: "aき"))
        }
    }

    func testMovingCursorAndInsert() throws {
        // Note: 末尾以外の位置で入力すると、入力+{cs}が入力される。
        // {cs}{cs}は{cs}に置換されるので、2つ以上が並ぶことはない
        // これにより、「nana|, なな|」「na|na, な|な」「nan|na, なn|な」「nanna|, なんあ|」となるようなエラーを防ぐことができる
        do {
            var c = ComposingText()
            sequentialInput(&c, sequence: "nana", inputStyle: .roman2kana)
            _ = c.moveCursorFromCursorPosition(count: -1)
            c.insertAtCursorPosition("n", inputStyle: .roman2kana)
            XCTAssertEqual(c.convertTarget, "なnな")
            _ = c.moveCursorFromCursorPosition(count: 1)
            XCTAssertEqual(c.convertTarget, "なnな")
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "n", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "a", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "n", inputStyle: .roman2kana),
                ComposingText.InputElement(piece: .compositionSeparator, inputStyle: .frozen),
                ComposingText.InputElement(character: "n", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "a", inputStyle: .roman2kana)
            ])
            XCTAssertEqual(c.convertTargetCursorPosition, 3)
        }
        do {
            // {cs}が2つ並ぶことはない
            var c = ComposingText()
            sequentialInput(&c, sequence: "nana", inputStyle: .roman2kana)
            _ = c.moveCursorFromCursorPosition(count: -1)
            c.insertAtCursorPosition("k", inputStyle: .roman2kana)
            XCTAssertEqual(c.convertTarget, "なkな")
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "n", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "a", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "k", inputStyle: .roman2kana),
                ComposingText.InputElement(piece: .compositionSeparator, inputStyle: .frozen),
                ComposingText.InputElement(character: "n", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "a", inputStyle: .roman2kana)
            ])
            XCTAssertEqual(c.convertTargetCursorPosition, 2)
            c.insertAtCursorPosition("a", inputStyle: .roman2kana)
            XCTAssertEqual(c.convertTarget, "なかな")
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "n", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "a", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "k", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "a", inputStyle: .roman2kana),
                ComposingText.InputElement(piece: .compositionSeparator, inputStyle: .frozen),
                ComposingText.InputElement(character: "n", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "a", inputStyle: .roman2kana)
            ])
            XCTAssertEqual(c.convertTargetCursorPosition, 2)
        }
        do {
            var c = ComposingText()
            sequentialInput(&c, sequence: "sai", inputStyle: .roman2kana)
            _ = c.moveCursorFromCursorPosition(count: -2)
            c.insertAtCursorPosition("xs", inputStyle: .roman2kana)
            _ = c.moveCursorFromCursorPosition(count: 2)
            c.insertAtCursorPosition("zu", inputStyle: .roman2kana)
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "x", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "s", inputStyle: .roman2kana),
                ComposingText.InputElement(piece: .compositionSeparator, inputStyle: .frozen),
                ComposingText.InputElement(character: "s", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "a", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "i", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "z", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "u", inputStyle: .roman2kana)
            ])
            XCTAssertEqual(c.convertTarget, "xsさいず")
            XCTAssertEqual(c.convertTargetCursorPosition, 5)
        }
        do {
            var c = ComposingText()
            sequentialInput(&c, sequence: "y", inputStyle: .roman2kana)
            _ = c.moveCursorFromCursorPosition(count: -1)
            c.insertAtCursorPosition("k", inputStyle: .roman2kana)
            _ = c.moveCursorFromCursorPosition(count: 2)
            c.insertAtCursorPosition("a", inputStyle: .roman2kana)
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "k", inputStyle: .roman2kana),
                ComposingText.InputElement(piece: .compositionSeparator, inputStyle: .frozen),
                ComposingText.InputElement(character: "y", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "a", inputStyle: .roman2kana)
            ])
            XCTAssertEqual(c.convertTarget, "kや")   // 「きゃ」にはならない
            XCTAssertEqual(c.convertTargetCursorPosition, 2)
        }
    }

    func testDeleteForward() throws {
        // ダイレクト
        do {
            var c = ComposingText()
            c.insertAtCursorPosition("あいうえお", inputStyle: .direct) // あいうえお|
            _ = c.moveCursorFromCursorPosition(count: -3)  // あい|うえお
            // 「う」を消す
            c.deleteForwardFromCursorPosition(count: 1)   // あい|えお
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "あ", inputStyle: .direct),
                ComposingText.InputElement(character: "い", inputStyle: .direct),
                ComposingText.InputElement(piece: .compositionSeparator, inputStyle: .frozen),
                ComposingText.InputElement(character: "え", inputStyle: .direct),
                ComposingText.InputElement(character: "お", inputStyle: .direct)
            ])
            XCTAssertEqual(c.convertTarget, "あいえお")
            XCTAssertEqual(c.convertTargetCursorPosition, 2)
        }

        // ローマ字（危険なケース）
        do {
            var c = ComposingText()
            c.insertAtCursorPosition("akafa", inputStyle: .roman2kana) // あかふぁ|
            _ = c.moveCursorFromCursorPosition(count: -1)  // あかふ|ぁ
            // 「ぁ」を消す
            c.deleteForwardFromCursorPosition(count: 1)   // あかふ
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "a", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "k", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "a", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "ふ", inputStyle: .frozen)
            ])
            XCTAssertEqual(c.convertTarget, "あかふ")
            XCTAssertEqual(c.convertTargetCursorPosition, 3)
        }
        // カスタム (危険なケース)
        do {
            let table = InputTable(baseMapping: [
                [.piece(.character("o"))]: [.character("お"), .character("は")],
                [.piece(.character("お")), .piece(.character("は")), .piece(.character("y"))]: [.character("お"), .character("は"), .character("よ"), .character("う")]
            ])
            InputStyleManager.registerInputStyle(table: table, for: "denowb")
            var c = ComposingText()
            sequentialInput(&c, sequence: "oy", inputStyle: .mapped(id: .tableName("denowb"))) // おはよう|
            _ = c.moveCursorFromCursorPosition(count: -3) // お|はよう
            // 「は」を消す
            c.deleteForwardFromCursorPosition(count: 1)   // お|よう
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "お", inputStyle: .frozen),
                ComposingText.InputElement(piece: .compositionSeparator, inputStyle: .frozen),
                ComposingText.InputElement(character: "よ", inputStyle: .frozen),
                ComposingText.InputElement(character: "う", inputStyle: .frozen)
            ])
            XCTAssertEqual(c.convertTarget, "およう")
            XCTAssertEqual(c.convertTargetCursorPosition, 1)
        }
        // カスタム (循環を含むケース)
        do {
            let table = InputTable(baseMapping: [
                [.piece(.character("a"))]: [.character("あ")],
                [.piece(.character("e"))]: [.character("え")],
                [.piece(.character("あ")), .piece(.character("i"))]: [.character("い")],
                [.piece(.character("い")), .piece(.character("u"))]: [.character("あ")]
            ])
            InputStyleManager.registerInputStyle(table: table, for: "custom_delete2")
            var c = ComposingText()
            sequentialInput(&c, sequence: "eaiu", inputStyle: .mapped(id: .tableName("custom_delete2"))) // えあ|
            _ = c.moveCursorFromCursorPosition(count: -1) // え|あ
            // 「あ」を消す
            c.deleteForwardFromCursorPosition(count: 1) // え|
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "e", inputStyle: .mapped(id: .tableName("custom_delete2")))
            ])
            XCTAssertEqual(c.convertTarget, "え")
            XCTAssertEqual(c.convertTargetCursorPosition, 1)
        }
    }

    func testMovingCursorAndDeleteForward() throws {
        // Note: 先端・末尾を含まない範囲を削除すると、削除位置に{cs}が入力される
        // {cs}{cs}は{cs}に置換されるので、2つ以上が並ぶことはない
        // これにより、「t|atu, t|あつ」「t|tu, t|つ」「ttu|, っつ|」となるようなエラーを防ぐことができる
        do {
            var c = ComposingText()
            sequentialInput(&c, sequence: "txsu", inputStyle: .roman2kana)
            _ = c.moveCursorFromCursorPosition(count: -2)
            c.deleteForwardFromCursorPosition(count: 1)
            _ = c.moveCursorFromCursorPosition(count: 1)
            c.insertAtCursorPosition("a", inputStyle: .roman2kana)
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "t", inputStyle: .roman2kana),
                ComposingText.InputElement(piece: .compositionSeparator, inputStyle: .frozen),
                ComposingText.InputElement(character: "s", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "u", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "a", inputStyle: .roman2kana)
            ])
            XCTAssertEqual(c.convertTarget, "tすあ")
            XCTAssertEqual(c.convertTargetCursorPosition, 3)
        }
        do {
            // {cs}が2つ並ぶことはない
            var c = ComposingText()
            sequentialInput(&c, sequence: "huransu", inputStyle: .roman2kana)
            XCTAssertEqual(c.convertTarget, "ふらんす")
            _ = c.moveCursorFromCursorPosition(count: -3)
            c.deleteForwardFromCursorPosition(count: 1)
            XCTAssertEqual(c.convertTarget, "ふんす")
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "h", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "u", inputStyle: .roman2kana),
                ComposingText.InputElement(piece: .compositionSeparator, inputStyle: .frozen),
                ComposingText.InputElement(character: "n", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "s", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "u", inputStyle: .roman2kana)
            ])
            XCTAssertEqual(c.convertTargetCursorPosition, 1)
            c.deleteForwardFromCursorPosition(count: 1)
            XCTAssertEqual(c.convertTarget, "ふす")
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "h", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "u", inputStyle: .roman2kana),
                ComposingText.InputElement(piece: .compositionSeparator, inputStyle: .frozen),
                ComposingText.InputElement(character: "す", inputStyle: .frozen)
            ])
            XCTAssertEqual(c.convertTargetCursorPosition, 1)
        }
        do {
            var c = ComposingText()
            sequentialInput(&c, sequence: "atst", inputStyle: .roman2kana)
            _ = c.moveCursorFromCursorPosition(count: -2)
            c.deleteForwardFromCursorPosition(count: 1)
            _ = c.moveCursorFromCursorPosition(count: 1)
            XCTAssertEqual(c.input, [
                ComposingText.InputElement(character: "a", inputStyle: .roman2kana),
                ComposingText.InputElement(character: "t", inputStyle: .roman2kana),
                ComposingText.InputElement(piece: .compositionSeparator, inputStyle: .frozen),
                ComposingText.InputElement(character: "t", inputStyle: .roman2kana)
            ])
            XCTAssertEqual(c.convertTarget, "あtt")   // 「あっt」にはならない
            XCTAssertEqual(c.convertTargetCursorPosition, 3)
        }
    }

    func testDifferenceSuffix() throws {
        do {
            var c1 = ComposingText()
            c1.insertAtCursorPosition("hasir", inputStyle: .roman2kana)

            var c2 = ComposingText()
            c2.insertAtCursorPosition("hasiru", inputStyle: .roman2kana)

            XCTAssertEqual(c2.differenceSuffix(to: c1).deletedInput, 0)
            XCTAssertEqual(c2.differenceSuffix(to: c1).addedInput, 1)
        }
        do {
            var c1 = ComposingText()
            c1.insertAtCursorPosition("tukatt", inputStyle: .roman2kana)

            var c2 = ComposingText()
            c2.insertAtCursorPosition("tukatte", inputStyle: .roman2kana)

            XCTAssertEqual(c2.differenceSuffix(to: c1).deletedInput, 0)
            XCTAssertEqual(c2.differenceSuffix(to: c1).addedInput, 1)
        }
    }

    func testIndexMap() throws {
        // ローマ字
        do {
            var c = ComposingText()
            sequentialInput(&c, sequence: "kyouhaiitenkida", inputStyle: .roman2kana)
            let map = c.inputIndexToSurfaceIndexMap()

            XCTAssertEqual(map[0], 0)     // ""
            XCTAssertEqual(map[1], nil)   // k
            XCTAssertEqual(map[2], nil)   // y
            XCTAssertEqual(map[3], 2)     // o
            XCTAssertEqual(map[4], 3)     // u
            XCTAssertEqual(map[5], nil)   // h
            XCTAssertEqual(map[6], 4)     // a
            XCTAssertEqual(map[7], 5)     // i
            XCTAssertEqual(map[8], 6)     // i
            XCTAssertEqual(map[9], nil)   // t
            XCTAssertEqual(map[10], 7)    // e
            XCTAssertEqual(map[11], nil)  // n
            XCTAssertEqual(map[12], nil)  // k
            XCTAssertEqual(map[13], 9)    // i
            XCTAssertEqual(map[14], nil)  // d
            XCTAssertEqual(map[15], 10)   // a
        }
        // ローマ字 (composition-separatorがあるケース)
        do {
            var c = ComposingText()
            sequentialInput(&c, sequence: "aka", inputStyle: .roman2kana)
            c.insertAtCursorPosition([.init(piece: .compositionSeparator, inputStyle: .roman2kana)])
            let map = c.inputIndexToSurfaceIndexMap()

            XCTAssertEqual(map[0], 0)     // ""
            XCTAssertEqual(map[1], 1)     // a
            XCTAssertEqual(map[2], nil)   // k
            XCTAssertEqual(map[3], 2)     // a
            XCTAssertEqual(map[4], 2)     // {cs}
        }
        // カスタム (循環を含むケース)
        do {
            let table = InputTable(baseMapping: [
                [.piece(.character("a"))]: [.character("あ")],
                [.piece(.character("i"))]: [.character("い")],
                [.piece(.character("あ")), .piece(.character("い")), .piece(.character("u"))]: [.character("あ")],
                [.piece(.character("e"))]: [.character("え")]
            ])
            InputStyleManager.registerInputStyle(table: table, for: "custom_indexmap_aiaiue")
            var c = ComposingText()
            sequentialInput(&c, sequence: "aiuaiue", inputStyle: .mapped(id: .tableName("custom_indexmap_aiaiue")))
            let map = c.inputIndexToSurfaceIndexMap()

            XCTAssertEqual(map[0], 0)     // ""
            XCTAssertEqual(map[1], nil)   // a
            XCTAssertEqual(map[2], nil)   // i
            XCTAssertEqual(map[3], 1)     // u
            XCTAssertEqual(map[4], nil)   // a
            XCTAssertEqual(map[5], nil)   // i
            XCTAssertEqual(map[6], 2)     // u
            XCTAssertEqual(map[7], 3)     // e
        }
        do {
            // ローマ字
            InputStyleManager.registerInputStyle(table: InputTable(baseMapping: [
                [.piece(.character("k")), .piece(.character("i"))]: [],
                [.piece(.character("a"))]: [.character("あ")]
            ] as Dictionary), for: "test-empty-ki")
            var c = ComposingText()
            sequentialInput(&c, sequence: "ki", inputStyle: .mapped(id: .tableName("test-empty-ki")))
            XCTAssertEqual(c.convertTarget, "")
            XCTAssertEqual(c.input.count, 2)
            let map = c.inputIndexToSurfaceIndexMap()
            XCTAssertEqual(map[0], 0)     // ""
            XCTAssertEqual(map[1], nil)   // k
            XCTAssertEqual(map[2], 0)     // i
        }
        // 逆引き
        do {
            var c = ComposingText()
            sequentialInput(&c, sequence: "sakujoshori", inputStyle: .roman2kana)
            let map = c.inputIndexToSurfaceIndexMap()
            let reversedMap = (0 ..< c.convertTarget.count + 1).compactMap {
                if map.values.contains($0) {
                    String(c.convertTarget.prefix($0))
                } else {
                    nil
                }
            }
            XCTAssertFalse(reversedMap.contains("さくじ"))
            XCTAssertFalse(reversedMap.contains("さくじょし"))
        }
    }

    func testNEndOfTextConversion() throws {
        let elements: [ComposingText.InputElement] = [
            .init(character: "n", inputStyle: .roman2kana),
            .init(piece: .compositionSeparator, inputStyle: .roman2kana)
        ]
        XCTAssertEqual(ComposingText.getConvertTarget(for: elements), "ん")
    }

    func testNEndOfTextComposition() throws {
        var c = ComposingText()
        c.insertAtCursorPosition("a", inputStyle: .roman2kana)
        c.insertAtCursorPosition("n", inputStyle: .roman2kana)
        XCTAssertEqual(c.convertTarget, "あn")
        c.insertAtCursorPosition([.init(piece: .compositionSeparator, inputStyle: .roman2kana)])
        XCTAssertEqual(c.convertTarget, "あん")
        c.insertAtCursorPosition("i", inputStyle: .roman2kana)
        XCTAssertEqual(c.convertTarget, "あんい")
        c.deleteBackwardFromCursorPosition(count: 1)
        XCTAssertEqual(c.convertTarget, "あん")
        c.deleteBackwardFromCursorPosition(count: 1)
        XCTAssertEqual(c.convertTarget, "あ")
        XCTAssertEqual(c.input, [.init(character: "a", inputStyle: .roman2kana)])
        c.insertAtCursorPosition([.init(piece: .compositionSeparator, inputStyle: .roman2kana)])
        XCTAssertEqual(c.convertTarget, "あ")
        c.insertAtCursorPosition([.init(piece: .compositionSeparator, inputStyle: .roman2kana)])
        XCTAssertEqual(c.convertTarget, "あ")
    }

    func testEndOfTextDeletion() throws {
        var c = ComposingText()
        c.insertAtCursorPosition("a", inputStyle: .roman2kana)
        c.insertAtCursorPosition("n", inputStyle: .roman2kana)
        XCTAssertEqual(c.convertTarget, "あn")
        c.insertAtCursorPosition([.init(piece: .compositionSeparator, inputStyle: .roman2kana)])
        c.insertAtCursorPosition([.init(piece: .compositionSeparator, inputStyle: .roman2kana)])
        c.insertAtCursorPosition([.init(piece: .compositionSeparator, inputStyle: .roman2kana)])
        c.insertAtCursorPosition([.init(piece: .compositionSeparator, inputStyle: .roman2kana)])
        c.insertAtCursorPosition([.init(piece: .compositionSeparator, inputStyle: .roman2kana)])
        XCTAssertEqual(c.convertTarget, "あん")
        c.deleteBackwardFromCursorPosition(count: 1)
        XCTAssertEqual(c.convertTarget, "あ")
        XCTAssertEqual(c.input, [.init(character: "a", inputStyle: .roman2kana)])
    }

    func testPrefixCompleteWithNInput() throws {
        var c = ComposingText()
        c.insertAtCursorPosition("d", inputStyle: .roman2kana)
        c.insertAtCursorPosition("a", inputStyle: .roman2kana)
        c.insertAtCursorPosition("n", inputStyle: .roman2kana)
        c.insertAtCursorPosition("b", inputStyle: .roman2kana)
        c.insertAtCursorPosition("a", inputStyle: .roman2kana)
        c.insertAtCursorPosition("s", inputStyle: .roman2kana)
        c.insertAtCursorPosition("u", inputStyle: .roman2kana)
        XCTAssertEqual(c.convertTarget, "だんばす")
        c.prefixComplete(composingCount: .surfaceCount(2))
        XCTAssertEqual(c.convertTarget, "ばす")
        XCTAssertEqual(c.input[0], .init(piece: .character("ば"), inputStyle: .frozen))
    }

    func testPrefixCompleteWithAZIK() throws {
        var c = ComposingText()
        c.insertAtCursorPosition("s", inputStyle: .mapped(id: .defaultAZIK))
        c.insertAtCursorPosition("z", inputStyle: .mapped(id: .defaultAZIK))
        c.insertAtCursorPosition("z", inputStyle: .mapped(id: .defaultAZIK))
        c.insertAtCursorPosition("z", inputStyle: .mapped(id: .defaultAZIK))
        XCTAssertEqual(c.convertTarget, "さんざん")
        c.prefixComplete(composingCount: .surfaceCount(3))
        XCTAssertEqual(c.convertTarget, "ん")
        XCTAssertEqual(c.input[0], .init(piece: .character("ん"), inputStyle: .frozen))
    }
}
