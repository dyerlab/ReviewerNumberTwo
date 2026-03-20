//
//  main.swift
//  ReviewerNumberTwo
//
//  Created by rodney on 3/19/26.
//

import ArgumentParser
import Foundation

struct ReviewerNumberTwo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reviewer",
        abstract: "Research paper corpus: embed, search, and analyze.",
        subcommands: [
            IngestCommand.self,
            SearchCommand.self,
            SimilarCommand.self,
            BenchmarkCommand.self
        ]
    )
}

ReviewerNumberTwo.main()
