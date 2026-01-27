//
//  MixedInputManager.swift
//  HamsterKeyboardKit
//
//  Created for nanomouse project
//  借鉴 AzooKey 的 ComposingText 设计，实现数字混合输入功能
//

import Foundation

/// 混合输入管理器 - 借鉴 AzooKey 的 ComposingText 设计
/// 用于管理拼音和数字的混合输入，使 "qian10ming" 能够显示候选词 "前10名"
public class MixedInputManager {

    /// 输入段类型
    public enum SegmentType: Equatable {
        case pinyin(String)   // 拼音段，需要 RIME 转换
        case literal(display: String, commit: String)  // 直接文本（数字、符号等）
    }

    /// 输入段
    public struct Segment: Equatable {
        public var type: SegmentType

        public var text: String {
            switch type {
            case .pinyin(let s): return s
            case .literal(let display, _): return display
            }
        }

        public var commitText: String {
            switch type {
            case .pinyin: return ""
            case .literal(_, let commit): return commit
            }
        }

        public var isPinyin: Bool {
            if case .pinyin = type { return true }
            return false
        }

        public var isLiteral: Bool {
            if case .literal = type { return true }
            return false
        }
    }

    /// 当前输入段列表
    public private(set) var segments: [Segment] = []

    /// 作为前缀显示但不参与候选组合的 literal 段数量
    public var literalPrefixSegmentCount: Int = 0

    /// 是否为空
    public var isEmpty: Bool {
        segments.isEmpty || segments.allSatisfy { $0.text.isEmpty }
    }

    /// 是否包含直接文本（数字等）
    public var hasLiteral: Bool {
        segments.contains { $0.isLiteral }
    }

    /// 最后一个段是否为拼音
    public var lastSegmentIsPinyin: Bool {
        segments.last?.isPinyin == true
    }

    /// 完整的显示文本
    public var displayText: String {
        guard !segments.isEmpty else { return "" }
        var result = ""
        let hasLiteralPrefix = effectiveLiteralPrefixCount > 0
        for index in segments.indices {
            let segment = segments[index]
            let nextSegment = index + 1 < segments.count ? segments[index + 1] : nil
            let prevSegment = index > 0 ? segments[index - 1] : nil

            switch segment.type {
            case .pinyin:
                if hasLiteralPrefix,
                   let prev = prevSegment,
                   prev.isLiteral,
                   !result.hasSuffix(" ")
                {
                    result += " "
                }
                result += segment.text

            case .literal(let display, _):
                let isDigit = isDigitLiteral(segment)
                let nextIsPinyin = nextSegment?.isPinyin == true
                if hasLiteralPrefix, isDigit, nextIsPinyin {
                    if prevSegment != nil, !result.hasSuffix(" ") {
                        result += " "
                    }
                    result += display
                    if !result.hasSuffix(" ") {
                        result += " "
                    }
                } else {
                    result += display
                }
            }
        }
        return result
    }

    /// 仅拼音部分（用于 RIME 查询）
    public var pinyinOnly: String {
        segments.compactMap {
            if case .pinyin(let s) = $0.type { return s }
            return nil
        }.joined()
    }

    /// 仅直接文本部分
    public var literalOnly: String {
        segments.compactMap {
            if case .literal(_, let commit) = $0.type { return commit }
            return nil
        }.joined()
    }

    private var effectiveLiteralPrefixCount: Int {
        if literalPrefixSegmentCount > 0 { return literalPrefixSegmentCount }
        if segments.count < 2 { return 0 }
        return segments.first?.isLiteral == true ? 1 : 0
    }

    /// 仅直接文本部分（排除前缀 literal 段）
    public var literalOnlyExcludingPrefix: String {
        let prefixCount = effectiveLiteralPrefixCount
        var result = ""
        var skipped = 0
        for segment in segments {
            if case .literal(_, let commit) = segment.type {
                if skipped < prefixCount {
                    skipped += 1
                    continue
                }
                result += commit
            }
        }
        return result
    }

    /// 前缀 literal 的显示文本
    public var literalPrefixText: String {
        let prefixCount = effectiveLiteralPrefixCount
        guard prefixCount > 0 else { return "" }
        var result = ""
        var taken = 0
        for segment in segments {
            if case .literal(let display, _) = segment.type {
                result += display
                taken += 1
                if taken >= prefixCount { break }
            } else if taken > 0 {
                break
            }
        }
        return result
    }

    /// 连续前缀 literal 段数量
    public var leadingLiteralSegmentCount: Int {
        var count = 0
        for segment in segments {
            if segment.isLiteral {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    public init() {}

    /// 在末尾插入文本
    /// - Parameters:
    ///   - text: 要插入的文本
    ///   - isLiteral: 是否为直接文本（数字等），如果为 false 则视为拼音
    public func insertAtCursorPosition(_ text: String, isLiteral: Bool = false) {
        if isLiteral {
            // 数字等直接文本
            // 检查最后一个段是否也是 literal，如果是则合并
            if let lastIndex = segments.indices.last,
               case .literal(let existingDisplay, let existingCommit) = segments[lastIndex].type {
                segments[lastIndex] = Segment(type: .literal(display: existingDisplay + text, commit: existingCommit + text))
            } else {
                segments.append(Segment(type: .literal(display: text, commit: text)))
            }
        } else {
            // 拼音字符，合并到最后一个拼音段或创建新段
            if let lastIndex = segments.indices.last,
               case .pinyin(let existing) = segments[lastIndex].type {
                segments[lastIndex] = Segment(type: .pinyin(existing + text))
            } else {
                segments.append(Segment(type: .pinyin(text)))
            }
        }
    }

    /// 根据显示文本重建分段（将数字与非数字 literal 拆分）
    public func rebuildSegments(from display: String) {
        reset()
        guard !display.isEmpty else { return }
        var currentType: SegmentType?
        var currentText = ""
        var currentCommit = ""

        func flush() {
            guard !currentText.isEmpty else { return }
            if let type = currentType {
                switch type {
                case .pinyin:
                    segments.append(Segment(type: .pinyin(currentText)))
                case .literal:
                    segments.append(Segment(type: .literal(display: currentText, commit: currentCommit)))
                }
            }
            currentType = nil
            currentText = ""
            currentCommit = ""
        }

        for ch in display {
            if ch == " " || ch == "'" { continue }
            let scalar = ch.unicodeScalars.first
            let isLetter = scalar.map { $0.isASCII && CharacterSet.letters.contains($0) } ?? false
            let isUmlaut = ch == "ü" || ch == "Ü"
            let isPinyin = isLetter || isUmlaut
            let isDigit = ch.isNumber

            if isPinyin {
                if currentType == nil {
                    currentType = .pinyin("")
                } else if case .literal = currentType {
                    flush()
                    currentType = .pinyin("")
                }
                currentText.append(ch)
                continue
            }

            // literal
            if currentType == nil {
                currentType = .literal(display: "", commit: "")
            } else if case .pinyin = currentType {
                flush()
                currentType = .literal(display: "", commit: "")
            } else if case .literal = currentType {
                let currentIsDigit = !currentCommit.isEmpty && currentCommit.allSatisfy { $0.isNumber }
                if currentIsDigit != isDigit {
                    flush()
                    currentType = .literal(display: "", commit: "")
                }
            }
            currentText.append(ch)
            currentCommit.append(ch)
        }

        flush()
    }

    /// 从末尾删除一个字符
    /// - Returns: 是否成功删除
    @discardableResult
    public func deleteBackward() -> Bool {
        guard !segments.isEmpty else { return false }

        // 从最后一个段删除
        guard let lastIndex = segments.indices.last else { return false }

        switch segments[lastIndex].type {
        case .pinyin(var s):
            if s.isEmpty {
                segments.removeLast()
            } else {
                s.removeLast()
                if s.isEmpty {
                    segments.removeLast()
                } else {
                    segments[lastIndex] = Segment(type: .pinyin(s))
                }
            }
        case .literal(var display, var commit):
            if display.isEmpty {
                segments.removeLast()
            } else {
                display.removeLast()
                if !commit.isEmpty {
                    commit.removeLast()
                }
                if display.isEmpty {
                    segments.removeLast()
                } else {
                    segments[lastIndex] = Segment(type: .literal(display: display, commit: commit))
                }
            }
        }

        return true
    }

    /// 重置所有输入
    public func reset() {
        segments.removeAll()
        literalPrefixSegmentCount = 0
    }

    /// 将最后一个拼音段提交为直接文本
    public func commitLastPinyinAsLiteral(_ commitText: String) {
        guard !commitText.isEmpty else { return }
        guard let pinyinIndex = segments.lastIndex(where: { $0.isPinyin }) else {
            segments.append(Segment(type: .literal(display: commitText, commit: commitText)))
            return
        }

        let displayText: String
        if case .pinyin(let raw) = segments[pinyinIndex].type {
            displayText = raw
        } else {
            displayText = commitText
        }

        segments[pinyinIndex] = Segment(type: .literal(display: displayText, commit: commitText))

        if pinyinIndex > 0,
           case .literal(let prevDisplay, let prevCommit) = segments[pinyinIndex - 1].type {
            let mergedDisplay = prevDisplay + displayText
            let mergedCommit = prevCommit + commitText
            segments[pinyinIndex - 1] = Segment(type: .literal(display: mergedDisplay, commit: mergedCommit))
            segments.remove(at: pinyinIndex)
        }

        let currentIndex = max(0, min(pinyinIndex, segments.count - 1))
        if currentIndex + 1 < segments.count,
           case .literal(let nextDisplay, let nextCommit) = segments[currentIndex + 1].type,
           case .literal(let currentDisplay, let currentCommit) = segments[currentIndex].type {
            segments[currentIndex] = Segment(
                type: .literal(display: currentDisplay + nextDisplay, commit: currentCommit + nextCommit)
            )
            segments.remove(at: currentIndex + 1)
        }
    }

    private func isPinyinLetter(_ scalar: UnicodeScalar) -> Bool {
        if scalar == "ü" || scalar == "Ü" { return true }
        return scalar.isASCII && CharacterSet.letters.contains(scalar)
    }

    private func isDigitLiteral(_ segment: Segment) -> Bool {
        if case .literal(_, let commit) = segment.type {
            return !commit.isEmpty && commit.allSatisfy { $0.isNumber }
        }
        return false
    }

    /// 前缀 literal 之后、拼音之前的数字 literal（用于数字插入到拼音中间的场景）
    public var digitLiteralBeforeFirstPinyin: String {
        let prefixCount = effectiveLiteralPrefixCount
        var skipped = 0
        var digits = ""
        var hasDigit = false

        for segment in segments {
            if segment.isPinyin {
                return hasDigit ? digits : ""
            }
            if case .literal(_, let commit) = segment.type {
                if skipped < prefixCount {
                    skipped += 1
                    continue
                }
                if !commit.isEmpty, commit.allSatisfy({ $0.isNumber }) {
                    digits += commit
                    hasDigit = true
                } else if !commit.isEmpty {
                    // 遇到非数字 literal，认为不属于数字插入场景
                    return ""
                }
            }
        }
        return ""
    }

    /// 替换或插入前缀 literal 之后、首个拼音之前的数字 literal
    /// - Returns: 是否成功（找到/插入）
    public func upsertDigitLiteralBeforeFirstPinyin(with text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let prefixCount = effectiveLiteralPrefixCount
        var skipped = 0
        var firstPinyinIndex: Int?

        for index in segments.indices {
            let segment = segments[index]
            if segment.isPinyin {
                firstPinyinIndex = index
                break
            }
            if case .literal = segment.type {
                if skipped < prefixCount {
                    skipped += 1
                    continue
                }
                if isDigitLiteral(segment) {
                    segments[index] = Segment(type: .literal(display: text, commit: text))
                    return true
                }
            }
        }

        guard let insertIndex = firstPinyinIndex else { return false }
        let safeIndex = min(max(insertIndex, prefixCount), segments.count)
        segments.insert(Segment(type: .literal(display: text, commit: text)), at: safeIndex)
        return true
    }

    /// 拼音段在中间数字之前的音节数量（用于过滤候选）
    public var syllableCountBeforeMiddleDigit: Int {
        var count = 0
        var seenPinyin = false
        for index in segments.indices {
            let segment = segments[index]
            if segment.isPinyin {
                seenPinyin = true
                count += countSyllables(segment.text)
                continue
            }
            if isDigitLiteral(segment), seenPinyin {
                let hasPinyinAfter = segments[(index + 1)...].contains { $0.isPinyin }
                return hasPinyinAfter ? count : 0
            }
        }
        return 0
    }

    /// 从拼音段起始处删除指定数量的拼音字母（用于分段选择后同步）
    public func trimLeadingPinyinLetters(_ count: Int) {
        guard count > 0 else { return }
        var remaining = count
        var newSegments: [Segment] = []

        for segment in segments {
            switch segment.type {
            case .literal:
                newSegments.append(segment)
            case .pinyin(let text):
                if remaining <= 0 {
                    newSegments.append(segment)
                    continue
                }
                var keptScalars = String.UnicodeScalarView()
                for scalar in text.unicodeScalars {
                    if remaining > 0, isPinyinLetter(scalar) {
                        remaining -= 1
                        continue
                    }
                    keptScalars.append(scalar)
                }
                let suffix = String(keptScalars)
                if !suffix.trimmingCharacters(in: .whitespaces).isEmpty {
                    newSegments.append(Segment(type: .pinyin(suffix)))
                }
            }
        }
        segments = newSegments
    }

    /// 将前缀拼音提交为直接文本，并保留后续段
    public func commitLeadingPinyinAsLiteral(committedCount: Int, commitText: String) {
        guard committedCount > 0, !commitText.isEmpty else { return }
        let insertIndex = segments.firstIndex(where: { $0.isPinyin }) ?? segments.count
        trimLeadingPinyinLetters(committedCount)

        let safeIndex = min(insertIndex, segments.count)
        segments.insert(Segment(type: .literal(display: commitText, commit: commitText)), at: safeIndex)

        let prevIndex = safeIndex - 1
        if prevIndex >= 0,
           case .literal(let display, let commit) = segments[prevIndex].type,
           !isDigitLiteral(segments[prevIndex])
        {
            segments[prevIndex] = Segment(type: .literal(display: display + commitText, commit: commit + commitText))
            segments.remove(at: safeIndex)
        }
    }

    /// 从拼音段起始处删除指定数量的拼音字符（用于分段选择后同步）
    public func trimLeadingPinyinCharacters(_ count: Int) {
        guard count > 0 else { return }
        var remaining = count
        var newSegments: [Segment] = []

        for segment in segments {
            switch segment.type {
            case .literal:
                newSegments.append(segment)
            case .pinyin(let text):
                if remaining <= 0 {
                    newSegments.append(segment)
                    continue
                }
                if remaining >= text.count {
                    remaining -= text.count
                    // 整段拼音被消费掉
                } else {
                    let suffix = String(text.dropFirst(remaining))
                    remaining = 0
                    if !suffix.isEmpty {
                        newSegments.append(Segment(type: .pinyin(suffix)))
                    }
                }
            }
        }
        segments = newSegments
    }

    /// 获取每个拼音段的字符范围信息
    /// - Returns: 数组，每个元素包含 (段索引, 开始位置, 长度)
    public func getPinyinSegmentRanges() -> [(segmentIndex: Int, start: Int, length: Int)] {
        var result: [(segmentIndex: Int, start: Int, length: Int)] = []
        var position = 0

        for (index, segment) in segments.enumerated() {
            let length = segment.text.count
            if segment.isPinyin {
                result.append((segmentIndex: index, start: position, length: length))
            }
            position += length
        }

        return result
    }

    /// 组合候选词
    /// 将 RIME 返回的候选词与直接文本（数字等）合并
    /// - Parameters:
    ///   - rimeCandidates: RIME 返回的候选词列表（针对 pinyinOnly 的查询结果）
    ///   - rimeComposition: RIME 返回的 composition 信息，用于确定分词
    /// - Returns: 组合后的候选词列表
    public func composeCandidates(rimeCandidates: [String], syllableCounts: [Int]? = nil) -> [String] {
        // 如果没有 literal 段，直接返回 RIME 候选
        guard hasLiteral else { return rimeCandidates }

        // 如果没有拼音段，返回直接文本
        let pinyinSegments = segments.filter { $0.isPinyin }
        guard !pinyinSegments.isEmpty else {
            return [literalOnly]
        }

        var results: [String] = []

        for candidate in rimeCandidates.prefix(20) {
            let composed = composeCandidate(candidate: candidate, syllableCounts: syllableCounts, includePrefixLiteral: false)
            if !composed.isEmpty {
                results.append(composed)
            }
        }

        return results
    }

    /// 组合单个候选词（可选是否包含前缀 literal）
    public func composeCandidateForDisplay(_ candidate: String, includePrefixLiteral: Bool) -> String {
        return composeCandidate(candidate: candidate, syllableCounts: nil, includePrefixLiteral: includePrefixLiteral)
    }

    /// 组合单个候选词
    private func composeCandidate(candidate: String, syllableCounts: [Int]?, includePrefixLiteral: Bool) -> String {
        var composed = ""
        var candidateChars = Array(candidate)
        var charIndex = 0
        var pinyinSegmentIndex = 0
        let prefixLimit = includePrefixLiteral ? 0 : effectiveLiteralPrefixCount
        var skippedPrefixLiterals = 0

        // 获取每个拼音段应该对应多少个汉字
        let pinyinSegments = segments.enumerated().filter { $0.element.isPinyin }
        var resolvedCounts: [Int] = []
        resolvedCounts.reserveCapacity(pinyinSegments.count)
        for (index, segment) in pinyinSegments.enumerated() {
            if let counts = syllableCounts, index < counts.count {
                resolvedCounts.append(counts[index])
            } else {
                resolvedCounts.append(countSyllables(segment.element.text))
            }
        }
        if let lastIndex = resolvedCounts.indices.last {
            let totalCount = resolvedCounts.reduce(0, +)
            let remainder = candidateChars.count - totalCount
            if remainder > 0 {
                resolvedCounts[lastIndex] += remainder
            }
        }

        for segment in segments {
            switch segment.type {
            case .pinyin(let pinyin):
                // 确定这段拼音对应多少个汉字
                let syllableCount: Int
                if pinyinSegmentIndex < resolvedCounts.count {
                    syllableCount = resolvedCounts[pinyinSegmentIndex]
                } else {
                    // 简单估算：按元音数量估算音节数
                    syllableCount = countSyllables(pinyin)
                }

                let charsToTake = min(syllableCount, candidateChars.count - charIndex)
                if charsToTake > 0 {
                    composed += String(candidateChars[charIndex..<(charIndex + charsToTake)])
                    charIndex += charsToTake
                }
                pinyinSegmentIndex += 1

            case .literal(_, let commit):
                if !includePrefixLiteral,
                   skippedPrefixLiterals < prefixLimit {
                    skippedPrefixLiterals += 1
                    continue
                }
                composed += commit
            }
        }

        // 如果还有剩余的候选字符，追加到末尾
        if charIndex < candidateChars.count {
            composed += String(candidateChars[charIndex...])
        }

        return composed
    }

    /// 简单估算拼音音节数
    /// - Parameter pinyin: 拼音字符串
    /// - Returns: 估算的音节数量
    public func countSyllables(_ pinyin: String) -> Int {
        // 简单实现：按元音数量估算
        let vowels = Set("aeiouüAEIOUÜ")
        var count = 0
        var prevWasVowel = false

        for char in pinyin {
            let isVowel = vowels.contains(char)
            if isVowel && !prevWasVowel {
                count += 1
            }
            prevWasVowel = isVowel
        }

        return max(1, count)
    }

    /// 获取用于上屏的完整文本
    /// - Parameter rimeCommitText: RIME 返回的上屏文本（仅包含拼音部分的转换结果）
    /// - Returns: 组合后的完整上屏文本
    public func getCommitText(rimeCommitText: String) -> String {
        guard hasLiteral else { return rimeCommitText }

    let normalizedCommit = rimeCommitText.replacingOccurrences(of: " ", with: "")
    let normalizedPinyin = pinyinOnly.replacingOccurrences(of: " ", with: "")
    if !normalizedCommit.isEmpty, normalizedCommit == normalizedPinyin {
        return displayText.replacingOccurrences(of: " ", with: "")
    }

        return composeCandidate(candidate: rimeCommitText, syllableCounts: nil, includePrefixLiteral: true)
    }
}
