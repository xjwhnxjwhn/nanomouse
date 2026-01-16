//
//  RegisteredNodeTests.swift
//  KanaKanjiConverterModuleTests
//
//  Created by ensan on 2023/01/31.
//  Copyright © 2023 ensan. All rights reserved.
//

@testable import KanaKanjiConverterModule
import XCTest

final class RegisteredNodeTests: XCTestCase {
    func testBOSNode() throws {
        let bos = RegisteredNode.BOSNode()
        XCTAssertEqual(bos.range, Lattice.LatticeRange.zero)
        XCTAssertNil(bos.prev)
        XCTAssertEqual(bos.totalValue, 0)
        XCTAssertEqual(bos.data.rcid, CIDData.BOS.cid)
    }

    func testFromLastCandidate() throws {
        let candidate = Candidate(text: "我輩は猫", value: -20, composingCount: .inputCount(7), lastMid: 100, data: [DicdataElement(word: "我輩は猫", ruby: "ワガハイハネコ", cid: CIDData.一般名詞.cid, mid: 100, value: -20)])
        let bos = RegisteredNode.fromLastCandidate(candidate)
        XCTAssertEqual(bos.range, Lattice.LatticeRange.zero)
        XCTAssertNil(bos.prev)
        XCTAssertEqual(bos.totalValue, 0)
        XCTAssertEqual(bos.data.rcid, CIDData.一般名詞.cid)
        XCTAssertEqual(bos.data.mid, 100)
    }

    func testGetCandidateData() throws {
        let bos = RegisteredNode.BOSNode()
        let node1 = RegisteredNode(
            data: DicdataElement(word: "我輩", ruby: "ワガハイ", cid: CIDData.一般名詞.cid, mid: 1, value: -5),
            registered: bos,
            totalValue: -10,
            range: .input(from: 0, to: 4)
        )
        let node2 = RegisteredNode(
            data: DicdataElement(word: "は", ruby: "ハ", cid: CIDData.係助詞ハ.cid, mid: 2, value: -2),
            registered: node1,
            totalValue: -13,
            range: .input(from: 4, to: 5)
        )
        let node3 = RegisteredNode(
            data: DicdataElement(word: "猫", ruby: "ネコ", cid: CIDData.一般名詞.cid, mid: 3, value: -4),
            registered: node2,
            totalValue: -20,
            range: .input(from: 5, to: 7)
        )
        let node4 = RegisteredNode(
            data: DicdataElement(word: "です", ruby: "デス", cid: CIDData.助動詞デス基本形.cid, mid: 4, value: -3),
            registered: node3,
            totalValue: -25,
            range: .input(from: 7, to: 9)
        )
        let result = node4.getCandidateData()
        var clause1 = ClauseDataUnit()
        clause1.text = "我輩は"
        clause1.nextLcid = CIDData.一般名詞.cid
        clause1.ranges = [.input(from: 0, to: 0), .input(from: 0, to: 4), .input(from: 4, to: 5)] // (0, 0) はBOSのためのダミー
        clause1.mid = 1

        var clause2 = ClauseDataUnit()
        clause2.text = "猫です"
        clause2.nextLcid = CIDData.EOS.cid
        clause2.ranges = [.input(from: 5, to: 7), .input(from: 7, to: 9)]
        clause2.mid = 3

        let expectedResult: CandidateData = CandidateData(
            clauses: [(clause1, -13), (clause2, -25)],
            data: [node1.data, node2.data, node3.data, node4.data]
        )
        XCTAssertEqual(result.data, expectedResult.data)
        XCTAssertEqual(result.clauses.map {$0.value}, expectedResult.clauses.map {$0.value})
        XCTAssertEqual(result.clauses.map {$0.clause}, expectedResult.clauses.map {$0.clause})
    }
}
