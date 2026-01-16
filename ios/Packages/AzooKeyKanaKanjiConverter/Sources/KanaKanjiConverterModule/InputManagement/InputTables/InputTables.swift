import OrderedCollections

enum InputTables {
    enum Helper {
        static func constructPieceMap(
            _ base: OrderedDictionary<String, String>,
            additionalMapping: OrderedDictionary<[InputTable.KeyElement], [InputTable.ValueElement]> = [:]
        ) -> OrderedDictionary<[InputTable.KeyElement], [InputTable.ValueElement]> {
            var map = OrderedDictionary<[InputTable.KeyElement], [InputTable.ValueElement]>(uniqueKeysWithValues: base.map { key, value in
                (key.map { .piece(.character($0)) }, value.map(InputTable.ValueElement.character))
            })
            map.merge(additionalMapping, uniquingKeysWith: { (first, _) in first })
            return map
        }
    }
}
