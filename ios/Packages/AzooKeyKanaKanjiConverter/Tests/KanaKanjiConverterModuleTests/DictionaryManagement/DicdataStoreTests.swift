@testable import KanaKanjiConverterModule
import SwiftUtils
import XCTest

final class DicdataStoreTests: XCTestCase {
    private func tmpDir(_ name: String) throws -> URL {
        let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let base = workspace.appendingPathComponent("TestsTmp", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent("AzooKeyTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func charMap(_ chars: [Character]) -> [Character: UInt8] {
        var map: [Character: UInt8] = [:]
        var next: UInt8 = 1
        for c in chars {
            if map[c] == nil {
                map[c] = next
                next += 1
            }
        }
        return map
    }

    private func toIDs(_ s: String, _ map: [Character: UInt8]) -> [UInt8] {
        s.compactMap { map[$0] }
    }

    private var dictionaryMockURL: URL {
        Bundle.module.resourceURL!.appendingPathComponent("DictionaryMock", isDirectory: true)
    }

    func testExportUserDictionaryAndReadViaDicdataStore() throws {
        // 1) Prepare sample user entries and export via DictionaryBuilder.exportDictionary
        let userDir = try tmpDir("user-export")
        defer {
            try? FileManager.default.removeItem(at: userDir)
        }

        let entries: [DicdataElement] = [
            DicdataElement(word: "亜", ruby: "あ", lcid: 10, rcid: 10, mid: 1, value: -100),
            DicdataElement(word: "阿", ruby: "あ", lcid: 10, rcid: 10, mid: 2, value: -90),
            DicdataElement(word: "蚊", ruby: "か", lcid: 13, rcid: 13, mid: 6, value: -50)
        ]
        let chars: [Character] = Array(entries.flatMapSet { Array($0.ruby) }).sorted()
        let cmap = charMap(chars)

        try DictionaryBuilder.exportDictionary(
            entries: entries,
            to: userDir,
            baseName: "user",
            shardByFirstCharacter: false,
            char2UInt8: cmap
        )

        // 2) Wire DicdataStore with DictionaryMock as system dictionary, but point user URL to our export
        let store = DicdataStore(dictionaryURL: dictionaryMockURL)
        let state = store.prepareState()
        state.updateUserDictionaryURL(userDir, forceReload: false)

        // 3) Load LOUDS for user via store and get node index using the same char-map used to export
        guard let louds = store.loadLOUDS(query: "user", state: state) else {
            return XCTFail("Failed to load LOUDS for user")
        }
        // Perfect match for ruby "あ"
        let idsA = toIDs("あ", cmap)
        guard let indexA = louds.searchNodeIndex(chars: idsA) else {
            return XCTFail("searchNodeIndex failed for user ruby 'あ'")
        }

        // 4) Fetch dicdata via DicdataStore API and validate entries + metadata
        let got = store.getDicdataFromLoudstxt3(identifier: "user", indices: [indexA], state: state)
        let wordsA = Set(got.filter { $0.ruby == "あ" }.map { $0.word })
        XCTAssertTrue(wordsA.isSuperset(of: ["亜", "阿"]))
        // User dictionary entries should carry isFromUserDictionary metadata
        XCTAssertTrue(got.allSatisfy { $0.metadata.contains(.isFromUserDictionary) })

        // 5) Also check ruby "か"
        if let indexK = louds.searchNodeIndex(chars: toIDs("か", cmap)) {
            let v = store.getDicdataFromLoudstxt3(identifier: "user", indices: [indexK], state: state)
            XCTAssertTrue(v.contains { $0.ruby == "か" && $0.word == "蚊" })
        } else {
            XCTFail("searchNodeIndex failed for user ruby 'か'")
        }
    }
}
