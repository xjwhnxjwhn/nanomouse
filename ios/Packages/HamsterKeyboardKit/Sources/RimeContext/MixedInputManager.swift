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
        segments.map { $0.text }.joined()
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
            let composed = composeCandidate(candidate: candidate, syllableCounts: syllableCounts)
            if !composed.isEmpty {
                results.append(composed)
            }
        }

        return results
    }

    /// 组合单个候选词
    private func composeCandidate(candidate: String, syllableCounts: [Int]?) -> String {
        var composed = ""
        var candidateChars = Array(candidate)
        var charIndex = 0
        var pinyinSegmentIndex = 0

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

        return composeCandidate(candidate: rimeCommitText, syllableCounts: nil)
    }
}
