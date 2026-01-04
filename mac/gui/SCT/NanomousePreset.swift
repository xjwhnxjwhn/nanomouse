import Foundation

enum NanomousePreset: String, CaseIterable, Identifiable {
    case rimeIce
    case lunaPinyinSimp
    case lunaPinyin
    case doublePinyin
    case doublePinyinFlypy

    var id: String { schemaId }

    var schemaId: String {
        switch self {
        case .rimeIce:
            return "rime_ice"
        case .lunaPinyinSimp:
            return "luna_pinyin_simp"
        case .lunaPinyin:
            return "luna_pinyin"
        case .doublePinyin:
            return "double_pinyin"
        case .doublePinyinFlypy:
            return "double_pinyin_flypy"
        }
    }

    var displayName: String {
        switch self {
        case .rimeIce:
            return "雾凇拼音"
        case .lunaPinyinSimp:
            return "明月拼音·简化字"
        case .lunaPinyin:
            return "明月拼音"
        case .doublePinyin:
            return "自然码双拼"
        case .doublePinyinFlypy:
            return "小鹤双拼"
        }
    }

    var description: String {
        return "启用 Nanomouse 拼音优化规则（ng→nn，uan→vn，uang→vnn）"
    }

    var fileName: String {
        "\(schemaId).custom.yaml"
    }

    var rules: [String] {
        [
            "derive/ng$/nn/",
            "derive/uan$/vn/",
            "derive/uang$/vnn/"
        ]
    }
}
