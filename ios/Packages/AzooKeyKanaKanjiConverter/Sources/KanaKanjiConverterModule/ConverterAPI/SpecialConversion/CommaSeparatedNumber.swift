import Foundation
import SwiftUtils

extension KanaKanjiConverter {
    func commaSeparatedNumberCandidates(_ inputData: ComposingText) -> [Candidate] {
        var text = inputData.convertTarget
        guard !text.isEmpty else { return [] }

        var negative = false
        if text.first == "-" {
            negative = true
            text.removeFirst()
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isNumber && $0.isASCII }) }) else {
            return []
        }
        let integerPart = parts[0]
        guard integerPart.count > 3 else { return [] }

        let reversed = Array(integerPart.reversed())
        var formatted = ""
        for (i, ch) in reversed.enumerated() {
            if i > 0 && i % 3 == 0 {
                formatted.append(",")
            }
            formatted.append(ch)
        }
        let integerString = String(formatted.reversed())
        var result = (negative ? "-" : "") + integerString
        if parts.count == 2 {
            let fractional = parts[1]
            result += "." + fractional
        }

        let ruby = inputData.convertTarget.toKatakana()
        let candidate = Candidate(
            text: result,
            value: -10,
            composingCount: .inputCount(inputData.input.count),
            lastMid: MIDData.一般.mid,
            data: [DicdataElement(word: result, ruby: ruby, cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -10)]
        )
        return [candidate]
    }
}
