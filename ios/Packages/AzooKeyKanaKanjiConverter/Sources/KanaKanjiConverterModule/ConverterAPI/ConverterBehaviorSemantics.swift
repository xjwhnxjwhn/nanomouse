public enum ConverterBehaviorSemantics: Sendable {
    /// 標準的な日本語入力のように、変換する候補を選ぶパターン
    case conversion
    /// iOSの英語入力のように、確定は不要だが、左右の文字列の置き換え候補が出てくるパターン
    case replacement([ReplacementTarget])

    public enum ReplacementTarget: UInt8, Sendable {
        case emoji
    }
}
