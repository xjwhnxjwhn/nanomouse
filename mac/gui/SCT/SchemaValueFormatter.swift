import Foundation

enum SchemaValueFormatter {
    static func string(from value: Any) -> String {
        switch value {
        case let bool as Bool:
            return bool ? L10n.on : L10n.off
        case let int as Int:
            return String(int)
        case let double as Double:
            return double.cleanString
        case let decimal as Decimal:
            return NSDecimalNumber(decimal: decimal).doubleValue.cleanString
        case let string as String:
            return string
        case let array as [Any]:
            return array.map { string(from: $0) }.joined(separator: ", ")
        case let dict as [String: Any]:
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return dict.description
        default:
            return String(describing: value)
        }
    }
}

extension Double {
    var cleanString: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? String(self)
    }
}
