//
//  IntegrationTests.swift
//  ReviewerNumberTwoTests
//
//  Integration tests using NLEmbeddingService (offline, no GPU, no downloads).
//  Covers the multi-provider loadAll pipeline end-to-end and the ingest
//  deduplication round-trip through CorpusStore.
//

import Testing
import NaturalLanguage
import Linguistics
import Foundation

// MARK: - Helpers

/// Collects progress callback invocations safely across concurrency boundaries.
private actor ProgressCollector {
    var calls: [(completed: Int, total: Int, filename: String)] = []
    func record(completed: Int, total: Int, filename: String) {
        calls.append((completed, total, filename))
    }
}

// MARK: - Tests

@Test func multiProviderLoadAllProgressAndOrdering() async throws {
    let dir = fixtureDirectory
    let service = try NLEmbeddingService(language: .english)
    let embedder = MultiProviderEmbedder(providers: [.nlEmbedding: service])

    let collector = ProgressCollector()

    let corpora = try await ManuscriptLoader.loadAll(
        from: dir,
        parts: [.Introduction],
        granularity: .sectionAndParagraphs,
        using: embedder
    ) { completed, total, filename in
        await collector.record(completed: completed, total: total, filename: filename)
    }

    let progressCalls = await collector.calls

    // Two fixture files → two corpora
    #expect(corpora.count == 2)

    // Progress callback fired exactly once per document
    #expect(progressCalls.count == 2)

    // completed counts are 1 and 2 (either document may finish first)
    let completedCounts = Set(progressCalls.map(\.completed))
    #expect(completedCounts == [1, 2])

    // total is always the full count
    #expect(progressCalls.allSatisfy { $0.total == 2 })

    // Results are in filename-ascending order regardless of completion order
    let filenames = corpora.compactMap { $0.metadata["filename"] }
    #expect(filenames == filenames.sorted(), "loadAll must return corpora in filename-ascending order")

    // Every embedding carries the expected metadata
    for corpus in corpora {
        let parts = corpus.embeddings.compactMap { $0.metadata["part"] }
        #expect(parts.allSatisfy { $0 == ManuscriptParts.Introduction.rawValue },
                "Only Introduction embeddings expected in \(corpus.label)")

        let indices = corpus.embeddings.compactMap { $0.metadata["sequence_index"].flatMap(Int.init) }
        #expect(indices.contains(0), "Full-section embedding (index 0) must be present")
        #expect(indices.contains(where: { $0 >= 1 }), "At least one paragraph embedding must be present")

        let providers = Set(corpus.embeddings.map(\.provider))
        #expect(providers == [.nlEmbedding])
    }
}

@Test func ingestDeduplicationRoundTrip() async throws {
    let dir = fixtureDirectory
    let service = try NLEmbeddingService(language: .english)
    let embedder = MultiProviderEmbedder(providers: [.nlEmbedding: service])

    let tmpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("cli_dedup_test_\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    // First pass: embed and write both papers
    let store = try CorpusStore(url: tmpURL)
    let firstPass = try await ManuscriptLoader.loadAll(
        from: dir, parts: [.Introduction], granularity: .sectionAndParagraphs, using: embedder
    )
    #expect(firstPass.count == 2)
    try store.write(firstPass)

    // Second pass: filterNew must exclude both (matched by filename)
    let existing = try store.readAll()
    let existingFilenames = Set(existing.compactMap { $0.metadata["filename"] })
    let existingDOIs      = Set(existing.compactMap { $0.metadata["doi"] }.filter { !$0.isEmpty })

    let secondPass = try await ManuscriptLoader.loadAll(
        from: dir, parts: [.Introduction], granularity: .sectionAndParagraphs, using: embedder
    )
    let newOnly = IngestCommand.filterNew(secondPass,
                                          existingFilenames: existingFilenames,
                                          existingDOIs: existingDOIs)
    #expect(newOnly.isEmpty, "filterNew must exclude all already-ingested documents on re-run")
}
