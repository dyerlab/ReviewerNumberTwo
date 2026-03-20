//
//  IngestCommand.swift
//  ReviewerNumberTwo
//
//  Embeds a directory of Markdown files and persists them to a SQLite corpus.
//  Supports multi-provider runs (comma-separated --providers) and section filtering
//  (--section) for focused hierarchical analysis across a paper corpus.
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

    @Option(name: .long, help: """
        Manuscript section to embed: Title, Abstract, Introduction, Methods, Results, \
        Discussion, Other. Omit to embed all sections.
        """)
    var section: ManuscriptParts? = nil

    @Option(name: .long, help: """
        Comma-separated embedding providers: nl, fdl, miniLM, bgeBase (default), bgeLarge, \
        mxbaiEmbedLarge, qwen3, nomic. Example: --providers fdl,nl,bgeBase
        """)
    var providers: String = "bgeBase"

    @Option(name: .long, help: "Embedding granularity: section, paragraph, or sectionAndParagraphs (default).")
    var granularity: EmbeddingGranularity = .sectionAndParagraphs

    func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        let dbURL    = URL(fileURLWithPath: db)

        let providerArgs = Self.parseProviders(providers)
        guard !providerArgs.isEmpty else {
            throw ValidationError(
                "No valid providers in '\(providers)'. Valid values: \(ProviderArgument.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }

        let providerOptions = providerArgs.map(\.option)
        let requestedParts  = section.map { [$0] }

        // Load existing corpus for incremental deduplication
        let store    = try CorpusStore(url: dbURL)
        let existing = try store.readAll()
        let existingFilenames = Set(existing.compactMap { $0.metadata["filename"] })
        let existingDOIs      = Set(existing.compactMap { $0.metadata["doi"] }.filter { !$0.isEmpty })

        // For FDL: collect section-level texts first so document-frequency cutoffs
        // are computed across manuscripts, not individual paragraphs.
        let fdlCorpusTexts: [String]?
        if providerOptions.contains(.fdlEmbedding) {
            print("Extracting section texts for FDL vocabulary…")
            let newTexts      = try ManuscriptLoader.extractTexts(from: inputURL, parts: requestedParts)
            let existingTexts = existing.flatMap { $0.embeddings.compactMap { $0.metadata["text"] } }
            fdlCorpusTexts    = existingTexts + newTexts
        } else {
            fdlCorpusTexts = nil
        }

        let providerNames = providerArgs.map(\.rawValue).joined(separator: ", ")
        print("Initializing embedding provider(s): \(providerNames)…")
        let embedder = try await MultiProviderEmbedder(options: providerOptions, corpus: fdlCorpusTexts)

        let sectionLabel = section.map { " · \($0.rawValue) only" } ?? ""
        print("Scanning \(inputURL.lastPathComponent) for Markdown files\(sectionLabel)…")

        let mdCount = (try? FileManager.default
            .contentsOfDirectory(atPath: inputURL.path)
            .filter { $0.hasSuffix(".md") }.count) ?? 0
        print("Found \(mdCount) document(s). Embedding in parallel…\n")

        let allCorpora = try await ManuscriptLoader.loadAll(
            from: inputURL,
            parts: requestedParts,
            granularity: granularity,
            using: embedder
        ) { completed, total, filename in
            if let line = Self.progressLine(completed: completed, total: total, filename: filename) {
                print(line)
            }
        }

        let newCorpora = Self.filterNew(allCorpora,
                                        existingFilenames: existingFilenames,
                                        existingDOIs: existingDOIs)

        let skipped = allCorpora.count - newCorpora.count
        guard !newCorpora.isEmpty else {
            print("All \(allCorpora.count) document(s) already ingested. Nothing to do.")
            return
        }

        if skipped > 0 { print("Skipping \(skipped) already-ingested document(s).") }

        print("Writing \(newCorpora.count) new document(s) to \(dbURL.lastPathComponent)…")
        try store.write(newCorpora)

        let totalEmbeddings = newCorpora.reduce(0) { $0 + $1.embeddings.count }
        print(
            "Done. Added \(newCorpora.count) document(s) / \(totalEmbeddings) embedding(s). " +
            "Corpus total: \(existing.count + newCorpora.count) document(s)."
        )
    }

    // MARK: - Helpers (internal for testing)

    /// Parses a comma-separated provider string into recognised `ProviderArgument` values.
    /// Whitespace around each token is trimmed. Unrecognised tokens are silently dropped.
    static func parseProviders(_ string: String) -> [ProviderArgument] {
        string
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { ProviderArgument(rawValue: $0) }
    }

    /// Returns only the corpora that are not already represented in the store,
    /// matching by non-empty DOI first, then by filename.
    static func filterNew(
        _ corpora: [Corpus],
        existingFilenames: Set<String>,
        existingDOIs: Set<String>
    ) -> [Corpus] {
        corpora.filter { corpus in
            if let doi = corpus.metadata["doi"], !doi.isEmpty,
               existingDOIs.contains(doi)               { return false }
            if let filename = corpus.metadata["filename"],
               existingFilenames.contains(filename)     { return false }
            return true
        }
    }

    /// Builds the progress-bar line for one completed document.
    /// Returns `nil` when `total` is zero to avoid division by zero.
    ///
    /// Example output: `"  [████████░░░░░░░░░░░░] 40%  2/5  Smith2021.md"`
    static func progressLine(completed: Int, total: Int, filename: String) -> String? {
        guard total > 0 else { return nil }
        let filled = completed * 20 / total
        let bar    = String(repeating: "█", count: filled)
                   + String(repeating: "░", count: 20 - filled)
        let pct    = completed * 100 / total
        return "  [\(bar)] \(pct)%  \(completed)/\(total)  \(filename)"
    }
}
