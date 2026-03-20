//
//  IngestCommand.swift
//  ReviewerNumberTwo
//
//  Embeds a directory of Markdown files and persists them to a SQLite corpus.
//  Skips documents already present (by DOI or filename) for incremental updates.
//

import ArgumentParser
import Foundation
import Linguistics

struct IngestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ingest",
        abstract: "Embed Markdown files and persist to a SQLite corpus database."
    )

    @Option(name: .long, help: "Directory of Markdown files (pre-converted from PDF).")
    var input: String

    @Option(name: .long, help: "Path to SQLite database (created if absent).")
    var db: String

    @Option(name: .long, help: "Embedding provider: nl, miniLM, bgeBase (default), bgeLarge, mxbaiEmbedLarge, fdl, qwen3, nomic.")
    var provider: ProviderArgument = .bgeBase

    @Option(name: .long, help: "Embedding granularity: section or paragraph (default).")
    var granularity: EmbeddingGranularity = .paragraph

    func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        let dbURL = URL(fileURLWithPath: db)

        // Load existing corpus first (needed for FDL vocabulary and incremental check)
        let store = try CorpusStore(url: dbURL)
        let existing = try store.readAll()
        let existingFilenames = Set(existing.compactMap { $0.metadata["filename"] })
        let existingDOIs = Set(existing.compactMap { $0.metadata["doi"] }.filter { !$0.isEmpty })

        // For FDL, build vocabulary from existing stored texts
        let fdlCorpus: [String]? = provider == .fdl
            ? existing.flatMap { $0.embeddings.compactMap { $0.metadata["text"] } }
            : nil

        print("Loading \(provider.option.displayName) embedding model…")
        let embeddingProvider = try await provider.option.makeProvider(corpus: fdlCorpus)

        print("Scanning \(inputURL.lastPathComponent) for Markdown files…")
        let allCorpora = try await ManuscriptLoader.loadAll(
            from: inputURL,
            granularity: granularity,
            using: embeddingProvider,
            as: provider.option
        )
        print("Found \(allCorpora.count) document(s).")

        let newCorpora = allCorpora.filter { corpus in
            if let doi = corpus.metadata["doi"], !doi.isEmpty, existingDOIs.contains(doi) {
                return false
            }
            if let filename = corpus.metadata["filename"], existingFilenames.contains(filename) {
                return false
            }
            return true
        }

        let skipped = allCorpora.count - newCorpora.count
        guard !newCorpora.isEmpty else {
            print("All \(allCorpora.count) document(s) already ingested. Nothing to do.")
            return
        }

        if skipped > 0 {
            print("Skipping \(skipped) already-ingested document(s).")
        }

        print("Writing \(newCorpora.count) new document(s) to \(dbURL.lastPathComponent)…")
        try store.write(newCorpora)

        let totalEmbeddings = newCorpora.reduce(0) { $0 + $1.embeddings.count }
        print("Done. Added \(newCorpora.count) document(s) / \(totalEmbeddings) embedding(s). Corpus total: \(existing.count + newCorpora.count) document(s).")
    }
}
