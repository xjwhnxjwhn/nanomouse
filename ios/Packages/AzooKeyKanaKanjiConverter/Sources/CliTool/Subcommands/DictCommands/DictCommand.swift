import ArgumentParser
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

extension Subcommands {
    struct Dict: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "dict",
            abstract: "Show dict information",
            subcommands: [Self.Read.self, Self.Build.self]
        )
    }
}
