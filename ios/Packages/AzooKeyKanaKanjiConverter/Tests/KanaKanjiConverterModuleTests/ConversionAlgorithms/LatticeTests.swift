@testable import KanaKanjiConverterModule
import XCTest

final class LatticeTests: XCTestCase {
    func sequentialInput(_ composingText: inout ComposingText, sequence: String, inputStyle: InputStyle) {
        for char in sequence {
            composingText.insertAtCursorPosition(String(char), inputStyle: inputStyle)
        }
    }

    func testDualIndexMap() throws {
        // ローマ字
        do {
            var c = ComposingText()
            sequentialInput(&c, sequence: "kyakkansi", inputStyle: .roman2kana)
            let latticeDualIndexMap = LatticeDualIndexMap(c)
            let indices = Array(latticeDualIndexMap.indices(inputCount: c.input.count, surfaceCount: c.convertTarget.count))
            XCTAssertEqual(indices[0], .bothIndex(inputIndex: 0, surfaceIndex: 0))     // ""
            XCTAssertEqual(indices[1], .inputIndex(1))     // k
            XCTAssertEqual(indices[2], .inputIndex(2))     // ky
            XCTAssertEqual(indices[3], .surfaceIndex(1))     // "きゃ"
            XCTAssertEqual(indices[4], .bothIndex(inputIndex: 3, surfaceIndex: 2))  // きゃ
            XCTAssertEqual(indices[5], .inputIndex(4))  // kyak
            XCTAssertEqual(indices[6], .inputIndex(5))  // kyakk
            XCTAssertEqual(indices[7], .surfaceIndex(3))  // きゃっ
            XCTAssertEqual(indices[8], .bothIndex(inputIndex: 6, surfaceIndex: 4))  // きゃっか
            XCTAssertEqual(indices[9], .inputIndex(7))  // kyakkan
            XCTAssertEqual(indices[10], .inputIndex(8))  // kyakkans
            XCTAssertEqual(indices[11], .surfaceIndex(5))  // きゃっかん
            XCTAssertEqual(indices.count, 12)  // 末尾は取り扱わない
        }
        // ローマ字
        do {
            var c = ComposingText()
            sequentialInput(&c, sequence: "kan", inputStyle: .roman2kana)
            c.insertAtCursorPosition([.init(piece: .compositionSeparator, inputStyle: .roman2kana)])
            let latticeDualIndexMap = LatticeDualIndexMap(c)
            let indices = Array(latticeDualIndexMap.indices(inputCount: c.input.count, surfaceCount: c.convertTarget.count))
            XCTAssertEqual(indices[0], .bothIndex(inputIndex: 0, surfaceIndex: 0))     // ""
            XCTAssertEqual(indices[1], .inputIndex(1))     // k
            XCTAssertEqual(indices[2], .bothIndex(inputIndex: 2, surfaceIndex: 1))     // ka
            XCTAssertEqual(indices[3], .inputIndex(3))     // "kan"
            XCTAssertEqual(indices.count, 4)  // 末尾は取り扱わない
        }
        // ローマ字
        do {
            var c = ComposingText()
            sequentialInput(&c, sequence: "kan", inputStyle: .roman2kana)
            c.insertAtCursorPosition([.init(piece: .compositionSeparator, inputStyle: .roman2kana)])
            sequentialInput(&c, sequence: "i", inputStyle: .roman2kana)
            let latticeDualIndexMap = LatticeDualIndexMap(c)
            let indices = Array(latticeDualIndexMap.indices(inputCount: c.input.count, surfaceCount: c.convertTarget.count))
            XCTAssertEqual(indices[0], .bothIndex(inputIndex: 0, surfaceIndex: 0))     // ""
            XCTAssertEqual(indices[1], .inputIndex(1))     // k
            XCTAssertEqual(indices[2], .bothIndex(inputIndex: 2, surfaceIndex: 1))     // ka
            XCTAssertEqual(indices[3], .inputIndex(3))     // "kan"
            XCTAssertEqual(indices[4], .bothIndex(inputIndex: 4, surfaceIndex: 2))     // "かん"
            XCTAssertEqual(indices.count, 5)  // 末尾は取り扱わない
        }
        // ローマ字
        do {
            InputStyleManager.registerInputStyle(table: InputTable(baseMapping: [
                [.piece(.character("k")), .piece(.character("i"))]: [],
                [.piece(.character("a"))]: [.character("あ")]
            ] as Dictionary), for: "test")
            var c = ComposingText()
            sequentialInput(&c, sequence: "ki", inputStyle: .mapped(id: .tableName("test")))
            XCTAssertEqual(c.convertTarget, "")
            XCTAssertEqual(c.input.count, 2)
            do {
                let latticeDualIndexMap = LatticeDualIndexMap(c)
                let indices = Array(latticeDualIndexMap.indices(inputCount: c.input.count, surfaceCount: c.convertTarget.count))
                XCTAssertEqual(indices[0], .inputIndex(0))     // "k-"
                XCTAssertEqual(indices[1], .inputIndex(1))     // "i-"
                XCTAssertEqual(indices.count, 2)  // 末尾は取り扱わない
            }
            sequentialInput(&c, sequence: "a", inputStyle: .mapped(id: .tableName("test")))
            XCTAssertEqual(c.convertTarget, "あ")
            XCTAssertEqual(c.input.count, 3)
            do {
                let latticeDualIndexMap = LatticeDualIndexMap(c)
                let map = c.inputIndexToSurfaceIndexMap()
                XCTAssertEqual(map[0], 0)     // ""
                XCTAssertEqual(map[1], 1)     // a-
                XCTAssertEqual(map[2], nil)     // a-
                XCTAssertEqual(map.count, 3)  // 末尾は取り扱わない
                let indices = Array(latticeDualIndexMap.indices(inputCount: c.input.count, surfaceCount: c.convertTarget.count))
                XCTAssertEqual(indices[0], .bothIndex(inputIndex: 0, surfaceIndex: 0))     // ""
                XCTAssertEqual(indices[1], .inputIndex(1))     // a-
                XCTAssertEqual(indices[2], .inputIndex(2))     // a-
                XCTAssertEqual(indices.count, 3)  // 末尾は取り扱わない
            }
        }
    }
}
