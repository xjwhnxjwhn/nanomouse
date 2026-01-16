import ArgumentParser
import Foundation

extension Subcommands {
    struct NGram: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ngram",
            abstract: "Use EfficientNGram Implementation",
            subcommands: [Self.Train.self, Self.Inference.self]
        )
    }
}
