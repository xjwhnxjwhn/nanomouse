//
//  ClauseDataUnitTests.swift
//  KanaKanjiConverterModuleTests
//
//  Created by ensan on 2022/12/30.
//  Copyright © 2022 ensan. All rights reserved.
//

@testable import KanaKanjiConverterModule
import XCTest

final class ClauseDataUnitTests: XCTestCase {
    func testMerge() throws {
        do {
            var unit1 = ClauseDataUnit()
            unit1.text = "僕が"
            unit1.ranges = [.input(from: 0, to: 3)]
            unit1.mid = 0
            unit1.nextLcid = 0

            var unit2 = ClauseDataUnit()
            unit2.text = "走る"
            unit2.ranges = [.input(from: 3, to: 6)]
            unit2.mid = 1
            unit2.nextLcid = 1

            unit1.merge(with: unit2)
            XCTAssertEqual(unit1.text, "僕が走る")
            XCTAssertEqual(unit1.ranges, [.input(from: 0, to: 3), .input(from: 3, to: 6)])
            XCTAssertEqual(unit1.nextLcid, 1)
            XCTAssertEqual(unit1.mid, 0)
        }

        do {
            var unit1 = ClauseDataUnit()
            unit1.text = "君は"
            unit1.ranges = [.input(from: 0, to: 3)]
            unit1.mid = 0
            unit1.nextLcid = 0

            var unit2 = ClauseDataUnit()
            unit2.text = "笑った"
            unit2.ranges = [.input(from: 3, to: 7)]
            unit2.mid = 3
            unit2.nextLcid = 3

            unit1.merge(with: unit2)
            XCTAssertEqual(unit1.text, "君は笑った")
            XCTAssertEqual(unit1.ranges, [.input(from: 0, to: 3), .input(from: 3, to: 7)])
            XCTAssertEqual(unit1.nextLcid, 3)
            XCTAssertEqual(unit1.mid, 0)
        }
    }
}
