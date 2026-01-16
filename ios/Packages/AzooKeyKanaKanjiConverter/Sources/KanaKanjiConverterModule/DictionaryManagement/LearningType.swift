public enum LearningType: Int, CaseIterable, Sendable {
    /// 学習情報は変換結果(output)に反映され、学習情報は更新(input)されます
    case inputAndOutput
    /// 学習情報は変換結果(output)に反映されるのみで、学習情報は更新されません
    case onlyOutput
    /// 学習情報は一切用いません
    case nothing

    package var needUpdateMemory: Bool {
        self == .inputAndOutput
    }

    var needUsingMemory: Bool {
        self != .nothing
    }
}
