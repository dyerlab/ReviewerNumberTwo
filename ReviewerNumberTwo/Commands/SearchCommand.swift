//
//  SearchCommand.swift
//  ReviewerNumberTwo
//
//  Two-stage semantic search: embedding retrieval followed by cross-encoder reranking.
//

import ArgumentParser
import Foundation
import Linguistics
import MatrixStuff

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Semantic search across the corpus with cross-encoder reranking."
    )

    @Option(name: .long, help: "Path to SQLite database.")
    var db: String

    @Option(name: .long, help: "Free-text query.")
    var query: String

    @Option(name: .long, help: "Number of results to return (default: 10).")
    var topK: Int = 10

    @Option(name: .long, help: "Embedding provider to search: nl, miniLM, bgeBase (default), bgeLarge, mxbaiEmbedLarge, fdl, qwen3, nomic.")
    var provider: ProviderArgument = .bgeBase

    func run() async throws {
        let dbURL = URL(fileURLWithPath: db)
        let store = try CorpusStore(url: dbURL)
        let allCorpora = try store.readAll()

        guard !allCorpora.isEmpty else {
            print("Corpus is empty. Run 'ingest' first.")
            return
        }

        // Flat list of (corpus, embedding) pairs for the requested provider
        typealias Hit = (corpus: Corpus, embedding: TextEmbedding)
        let candidates: [Hit] = allCorpora.flatMap { corpus in
            corpus.embeddings
                .filter { $0.provider == provider.option }
                .map { (corpus, $0) }
        }

        guard !candidates.isEmpty else {
            print("No embeddings found for provider '\(provider.rawValue)'. Re-run 'ingest' with --provider \(provider.rawValue).")
            return
        }

        // For FDL, build vocabulary from stored texts
        let fdlCorpus: [String]? = provider == .fdl
            ? candidates.compactMap { $0.embedding.metadata["text"] }
            : nil

        print("Loading \(provider.option.displayName) embedding model…")
        let embeddingProvider = try await provider.option.makeProvider(corpus: fdlCorpus)

        print("Embedding query…")
        let rawQuery = try await embeddingProvider.embed(query)
        let queryVector = rawQuery.normal   // L2-normalize; safe for both FDL and pre-normalized vectors

        // Stage 1: cosine similarity retrieval (dot product of normalized vectors = cosine similarity)
        let isFDL = provider == .fdl
        let scored: [(Hit, Double)] = candidates.map { hit in
            let stored = isFDL ? hit.embedding.vector.normal : hit.embedding.vector
            return (hit, queryVector .* stored)
        }

        let candidateCount = min(topK * 5, scored.count)
        let topCandidates = scored
            .sorted { $0.1 > $1.1 }
            .prefix(candidateCount)
            .map(\.0)

        // Stage 2: cross-encoder reranking
        print("Reranking \(topCandidates.count) candidates with cross-encoder…")
        let reranker = try await MLXCrossEncoderReranker()
        let reranked = try await reranker.rerank(
            query: query,
            items: Array(topCandidates),
            topK: topK
        ) { hit in
            hit.embedding.metadata["text"] ?? ""
        }

        // Output
        print("\nTop \(reranked.count) result(s) for: \"\(query)\"\n")
        for (i, result) in reranked.enumerated() {
            let hit = result.item
            let part = hit.embedding.metadata["part"] ?? "—"
            let text = hit.embedding.metadata["text"] ?? ""
            let snippet = String(text.prefix(240))
            let ellipsis = text.count > 240 ? "…" : ""
            print("[\(i + 1)] \(hit.corpus.label)")
            print("    Section : \(part)")
            print("    Score   : \(String(format: "%.4f", result.score))")
            print("    \(snippet)\(ellipsis)")
            print()
        }
    }
}
