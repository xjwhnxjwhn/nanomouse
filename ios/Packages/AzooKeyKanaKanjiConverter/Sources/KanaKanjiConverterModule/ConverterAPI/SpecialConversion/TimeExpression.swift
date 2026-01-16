import Foundation

extension KanaKanjiConverter {
    func convertToTimeExpression(_ inputData: ComposingText) -> [Candidate] {
        var candidates: [Candidate] = []
        let numberString = inputData.convertTarget

        // Check if all chars are digit.
        if numberString.contains(where: { !($0.isNumber && $0.isASCII) }) {
            return []
        }
        if numberString.count == 3 {
            let firstDigit = Int(numberString.prefix(1))!
            let lastTwoDigits = Int(numberString.suffix(2))!
            if (0...9).contains(firstDigit) && (0...59).contains(lastTwoDigits) {
                let timeExpression = "\(firstDigit):\(String(format: "%02d", lastTwoDigits))"
                let candidate = Candidate(
                    text: timeExpression,
                    value: -10,
                    composingCount: .surfaceCount(numberString.count),
                    lastMid: MIDData.一般.mid,
                    data: [DicdataElement(word: timeExpression, ruby: numberString, cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -10)]
                )
                candidates.append(candidate)
            }
        } else if numberString.count == 4 {
            let firstTwoDigits = Int(numberString.prefix(2))!
            let lastTwoDigits = Int(numberString.suffix(2))!
            if (0...24).contains(firstTwoDigits) && (0...59).contains(lastTwoDigits) {
                let timeExpression = "\(String(format: "%02d", firstTwoDigits)):\(String(format: "%02d", lastTwoDigits))"
                let candidate = Candidate(
                    text: timeExpression,
                    value: -10,
                    composingCount: .surfaceCount(numberString.count),
                    lastMid: MIDData.一般.mid,
                    data: [DicdataElement(word: timeExpression, ruby: numberString, cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -10)]
                )
                candidates.append(candidate)
            }
        }
        return candidates
    }
}
