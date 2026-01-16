import SwiftUtils

struct TypoCorrectionGenerator: Sendable {
    init(inputs: [ComposingText.InputElement], range: ProcessRange) {
        self.maxPenalty = 3.5 * 3
        self.inputs = inputs
        self.range = range

        let count = self.range.rightIndexRange.endIndex - range.leftIndex
        self.count = count
        self.nodes = (0..<count).map {(i: Int) in
            Self.lengths.flatMap {(k: Int) -> [TypoCandidate] in
                let j = i + k
                if count <= j {
                    return []
                }
                return Self.getTypo(inputs[range.leftIndex + i ... range.leftIndex + j])
            }
        }
        // 深さ優先で列挙する
        var leftConvertTargetElements: [ComposingText.ConvertTargetElement] = []
        for element in inputs[0 ..< range.leftIndex] {
            ComposingText.updateConvertTargetElements(currentElements: &leftConvertTargetElements, newElement: element)
        }
        let actualLeftConvertTarget = leftConvertTargetElements.reduce(into: "") { $0 += $1.string}

        self.stack = nodes[0].compactMap { typoCandidate in
            var convertTargetElements = [ComposingText.ConvertTargetElement]()
            var fullConvertTargetElements = leftConvertTargetElements
            for element in typoCandidate.inputElements {
                ComposingText.updateConvertTargetElements(currentElements: &convertTargetElements, newElement: element)
                ComposingText.updateConvertTargetElements(currentElements: &fullConvertTargetElements, newElement: element)
            }
            let fullConvertTarget = fullConvertTargetElements.reduce(into: "") { $0 += $1.string}
            let convertTarget = convertTargetElements.reduce(into: "") { $0 += $1.string}

            if fullConvertTarget == actualLeftConvertTarget + convertTarget {
                return (convertTargetElements, typoCandidate.inputElements.count, typoCandidate.weight)
            } else {
                return nil
            }
        }
    }

    let maxPenalty: PValue
    let inputs: [ComposingText.InputElement]
    let range: ProcessRange
    let nodes: [[TypoCandidate]]
    let count: Int

    struct ProcessRange: Sendable, Equatable {
        var leftIndex: Int
        var rightIndexRange: Range<Int>
    }

    var stack: [(convertTargetElements: [ComposingText.ConvertTargetElement], count: Int, penalty: PValue)]

    private static func check(
        _ leftConvertTargetElements: [ComposingText.ConvertTargetElement],
        isPrefixOf rightConvertTargetElements: [ComposingText.ConvertTargetElement]
    ) -> Bool {
        if leftConvertTargetElements.count > rightConvertTargetElements.count {
            // 常に不成立
            return false
        } else if leftConvertTargetElements.count == rightConvertTargetElements.count {
            let lastIndex = leftConvertTargetElements.count - 1
            if lastIndex == -1 {
                // この場合、両者emptyの配列なのでtrueを返す。
                return true
            }
            // 最後の1つのエレメントがprefixの関係にあれば成立
            for (lhs, rhs) in zip(leftConvertTargetElements[0 ..< lastIndex], rightConvertTargetElements[0 ..< lastIndex]) {
                if lhs != rhs {
                    return false
                }
            }
            if leftConvertTargetElements[lastIndex].inputStyle != rightConvertTargetElements[lastIndex].inputStyle {
                return false
            }
            return rightConvertTargetElements[lastIndex].string.hasPrefix(leftConvertTargetElements[lastIndex].string)
        } else {
            // leftConvertTargetElementsのインデックスの範囲ですべて一致していればprefixが成立
            for (lhs, rhs) in zip(leftConvertTargetElements, rightConvertTargetElements[0 ..< leftConvertTargetElements.endIndex]) {
                if lhs != rhs {
                    return false
                }
            }
            return true
        }
    }

    /// `target`で始まる場合は到達不可能であることを知らせる
    mutating func setUnreachablePath(target: some Collection<Character>) {
        // Materialize once for random access comparisons
        let targetArray: [Character] = Array(target)
        if targetArray.isEmpty { return }

        self.stack.removeAll { (convertTargetElements, _, _) in
            var matched = 0

            for item in convertTargetElements {
                // Determine how many characters of `item.string` are stable
                let s = item.string
                var stableCount = s.count
                switch item.inputStyle {
                case .direct:
                    break
                case .roman2kana, .mapped:
                    // Use cached table when available to avoid repeated lookups
                    let table: InputTable = if let cached = item.cachedTable {
                        cached
                    } else if case let .mapped(id) = item.inputStyle {
                        InputStyleManager.shared.table(for: id)
                    } else {
                        InputStyleManager.shared.table(for: .defaultRomanToKana)
                    }
                    if !s.isEmpty && table.maxUnstableSuffixLength > 0 {
                        let maxLen = min(table.maxUnstableSuffixLength, s.count)
                        // Find the longest unstable suffix; subtract its length
                        var remove = 0
                        var idx = maxLen
                        while idx >= 1 {
                            // Construct a tiny suffix array for set membership; lengths are small
                            let tail = Array(s[(s.count - idx)...])
                            if table.unstableSuffixes.contains(tail) {
                                remove = idx
                                break
                            }
                            idx -= 1
                        }
                        stableCount -= remove
                    }
                }

                if stableCount > 0 {
                    // Compare only up to remaining target length and stable chars
                    let need = min(stableCount, targetArray.count - matched)
                    if need > 0 {
                        // Fast element-wise compare; bail on first mismatch
                        for i in 0 ..< need {
                            if s[i] != targetArray[matched + i] {
                                // Mismatch before covering target → keep (reachable)
                                return false
                            }
                        }
                        matched += need
                        if matched >= targetArray.count {
                            // Stable part fully covers target prefix → unreachable → remove
                            return true
                        }
                    }
                }

                // If we encountered an unstable tail (stableCount < s.count), we stop extending here.
                if stableCount < s.count {
                    break
                }
            }
            // Did not fully match target with stable prefix → keep
            return false
        }
    }

    mutating func next() -> ([Character], (endIndex: Lattice.LatticeIndex, penalty: PValue))? {
        while let (convertTargetElements, count, penalty) = self.stack.popLast() {
            var result: ([Character], (endIndex: Lattice.LatticeIndex, penalty: PValue))?
            if self.range.rightIndexRange.contains(count + self.range.leftIndex - 1) {
                let originalConvertTarget = convertTargetElements.reduce(into: []) { $0 += $1.string.map { $0.toKatakana() } }
                if self.range.leftIndex + count < self.inputs.endIndex {
                    var newConvertTargetElements = convertTargetElements
                    ComposingText.updateConvertTargetElements(currentElements: &newConvertTargetElements, newElement: inputs[self.range.leftIndex + count])
                    if Self.check(convertTargetElements, isPrefixOf: newConvertTargetElements) {
                        result = (originalConvertTarget, (.input(count + self.range.leftIndex - 1), penalty))
                    }
                } else {
                    result = (originalConvertTarget, (.input(count + self.range.leftIndex - 1), penalty))
                }
            }
            // エスケープ
            if self.nodes.endIndex <= count {
                if let result {
                    return result
                } else {
                    continue
                }
            }
            // 訂正数上限(3個)
            if penalty >= maxPenalty {
                let element = inputs[self.range.leftIndex + count]
                let correct = switch element.piece {
                case let .character(c):
                    ComposingText.InputElement(piece: .character(c.toKatakana()), inputStyle: element.inputStyle)
                case let .key(intention: cint, input: cinp, modifiers: _):
                    ComposingText.InputElement(piece: .character((cint ?? cinp).toKatakana()), inputStyle: element.inputStyle)
                case _:
                    element
                }
                // +1 for `correct`
                if count + 1 > self.nodes.endIndex {
                    if let result {
                        return result
                    } else {
                        continue
                    }
                }
                var convertTargetElements = convertTargetElements
                ComposingText.updateConvertTargetElements(currentElements: &convertTargetElements, newElement: correct)
                stack.append((convertTargetElements, count + 1, penalty))
            } else {
                // ノード数は高々1, 2なので、for loopを回す方が効率が良い
                for node in self.nodes[count] where count + node.inputElements.count <= self.nodes.endIndex {
                    var convertTargetElements = convertTargetElements
                    for element in node.inputElements {
                        ComposingText.updateConvertTargetElements(currentElements: &convertTargetElements, newElement: element)
                    }
                    stack.append((
                        convertTargetElements: convertTargetElements,
                        count: count + node.inputElements.count,
                        penalty: penalty + node.weight
                    ))
                }
            }
            // このループで出力すべきものがある場合は出力する（yield）
            if let result {
                return result
            }
        }
        return nil
    }

    private enum InputStylesType {
        case none
        case onlyDirect
        case onlyRoman2KanaCompatible
        case other
    }

    private static func getTypo(_ elements: some Collection<ComposingText.InputElement>) -> [TypoCandidate] {
        guard !elements.isEmpty else {
            return []
        }
        lazy var key = elements.reduce(into: "") {
            switch $1.piece {
            case let .character(c):
                $0.append(c.toKatakana())
            case let .key(intention: cint, input: cinp, modifiers: _):
                $0.append((cint ?? cinp).toKatakana())
            case _:
                break
            }
        }

        let inputStylesType = elements.reduce(InputStylesType.none) { (result, element) in
            switch (result, element.inputStyle) {
            case (.other, _): .other
            case (.onlyDirect, .direct): .onlyDirect
            case (.onlyDirect, _): .other
            case (.onlyRoman2KanaCompatible, .roman2kana), (.onlyRoman2KanaCompatible, .mapped(id: .defaultRomanToKana)): .onlyRoman2KanaCompatible
            case (.onlyRoman2KanaCompatible, _): .other
            case (.none, .direct): .onlyDirect
            case (.none, .roman2kana), (.none, .mapped(id: .defaultRomanToKana)): .onlyRoman2KanaCompatible
            case (.none, _): .other
            }
        }
        switch inputStylesType {
        case .onlyDirect:
            let dictionary: [String: [TypoCandidate]] = Self.directPossibleTypo
            if key.count == 1 {
                var result = dictionary[key, default: []]
                // そのまま
                result.append(TypoCandidate(inputElements: key.map {.init(character: $0, inputStyle: .direct)}, weight: 0))
                return result
            } else {
                return dictionary[key, default: []]
            }
        case .onlyRoman2KanaCompatible:
            let dictionary: [String: [TypoCandidate]] = Self.roman2KanaPossibleTypo
            if key.count == 1 {
                var result = dictionary[key, default: []]
                // そのまま
                result.append(TypoCandidate(inputElements: key.map {.init(character: $0, inputStyle: .roman2kana)}, weight: 0))
                return result
            } else {
                return dictionary[key, default: []]
            }
        case .none, .other:
            // `.mapped`や、混ざっているケースでここに到達する
            return if elements.count == 1 {
                [
                    TypoCandidate(inputElements: [elements.first!], weight: 0)
                ]
            } else {
                []
            }
        }
    }

    fileprivate static let lengths = [0, 1]

    private struct TypoUnit: Equatable {
        var value: String
        var weight: PValue

        init(_ value: String, weight: PValue = 3.5) {
            self.value = value
            self.weight = weight
        }
    }

    struct TypoCandidate: Sendable, Equatable {
        var inputElements: [ComposingText.InputElement]
        var weight: PValue
    }

    /// ダイレクト入力用
    private static let directPossibleTypo: [String: [TypoCandidate]] = [
        "カ": [TypoUnit("ガ", weight: 7.0)],
        "キ": [TypoUnit("ギ")],
        "ク": [TypoUnit("グ")],
        "ケ": [TypoUnit("ゲ")],
        "コ": [TypoUnit("ゴ")],
        "サ": [TypoUnit("ザ")],
        "シ": [TypoUnit("ジ")],
        "ス": [TypoUnit("ズ")],
        "セ": [TypoUnit("ゼ")],
        "ソ": [TypoUnit("ゾ")],
        "タ": [TypoUnit("ダ", weight: 6.0)],
        "チ": [TypoUnit("ヂ")],
        "ツ": [TypoUnit("ッ", weight: 6.0), TypoUnit("ヅ", weight: 4.5)],
        "テ": [TypoUnit("デ", weight: 6.0)],
        "ト": [TypoUnit("ド", weight: 4.5)],
        "ハ": [TypoUnit("バ", weight: 4.5), TypoUnit("パ", weight: 6.0)],
        "ヒ": [TypoUnit("ビ"), TypoUnit("ピ", weight: 4.5)],
        "フ": [TypoUnit("ブ"), TypoUnit("プ", weight: 4.5)],
        "ヘ": [TypoUnit("ベ"), TypoUnit("ペ", weight: 4.5)],
        "ホ": [TypoUnit("ボ"), TypoUnit("ポ", weight: 4.5)],
        "バ": [TypoUnit("パ")],
        "ビ": [TypoUnit("ピ")],
        "ブ": [TypoUnit("プ")],
        "ベ": [TypoUnit("ペ")],
        "ボ": [TypoUnit("ポ")],
        "ヤ": [TypoUnit("ャ")],
        "ユ": [TypoUnit("ュ")],
        "ヨ": [TypoUnit("ョ")]
    ].mapValues {
        $0.map {
            TypoCandidate(
                inputElements: $0.value.map { ComposingText.InputElement(piece: .character($0), inputStyle: .direct) },
                weight: $0.weight
            )
        }
    }

    private static let roman2KanaPossibleTypo: [String: [TypoCandidate]] = [
        "bs": ["ba"],
        "no": ["bo"],
        "li": ["ki"],
        "lo": ["ko"],
        "lu": ["ku"],
        "my": ["mu"],
        "tp": ["to"],
        "ts": ["ta"],
        "wi": ["wo"],
        "pu": ["ou"]
    ].mapValues {
        $0.map {
            TypoCandidate(
                inputElements: $0.map { ComposingText.InputElement(piece: .character($0), inputStyle: .roman2kana) },
                weight: 3.5
            )
        }
    }
}
