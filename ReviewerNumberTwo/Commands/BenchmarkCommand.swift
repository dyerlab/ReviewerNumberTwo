//
//  BenchmarkCommand.swift
//  ReviewerNumberTwo
//
//  Two modes:
//  1) Without --db: runs EmbeddingBenchmark against a provider on scientific test pairs.
//  2) With --db:    also prints corpus statistics (document count, section distribution,
//                   embedding dimensions stored).
//

import ArgumentParser
import Foundation
import Linguistics

struct BenchmarkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "Evaluate an embedding provider and summarize corpus statistics."
    )

    @Option(name: .long, help: "Embedding provider to benchmark: nl, miniLM, bgeBase (default), bgeLarge, mxbaiEmbedLarge, fdl, qwen3, nomic.")
    var provider: ProviderArgument = .bgeBase

    @Option(name: .long, help: "Path to SQLite database (optional — shows corpus stats when provided).")
    var db: String?

    func run() async throws {

        // ── Corpus statistics ──────────────────────────────────────────────
        if let dbPath = db {
            let store = try CorpusStore(url: URL(fileURLWithPath: dbPath))
            let corpora = try store.readAll()

            print("── Corpus Statistics ──────────────────────────────────────")
            print("Documents  : \(corpora.count)")

            let totalEmbeddings = corpora.reduce(0) { $0 + $1.embeddings.count }
            print("Embeddings : \(totalEmbeddings)")

            // Section distribution
            var partCounts: [String: Int] = [:]
            var dimensionSet: Set<Int> = []
            for corpus in corpora {
                for emb in corpus.embeddings {
                    let part = emb.metadata["part"] ?? "unknown"
                    partCounts[part, default: 0] += 1
                    dimensionSet.insert(emb.vector.count)
                }
            }
            print("Dimensions : \(dimensionSet.sorted().map(String.init).joined(separator: ", "))")
            print("\nSection distribution:")
            for (part, count) in partCounts.sorted(by: { $0.value > $1.value }) {
                print("  \(part.padding(toLength: 20, withPad: " ", startingAt: 0)) \(count)")
            }

            // Provider breakdown
            var providerCounts: [String: Int] = [:]
            for corpus in corpora {
                for emb in corpus.embeddings {
                    providerCounts[emb.provider.displayName, default: 0] += 1
                }
            }
            print("\nProvider breakdown:")
            for (name, count) in providerCounts.sorted(by: { $0.value > $1.value }) {
                print("  \(name.padding(toLength: 24, withPad: " ", startingAt: 0)) \(count)")
            }
            print()
        }

        // ── Embedding benchmark ────────────────────────────────────────────
        print("── Embedding Benchmark: \(provider.option.displayName) ──────────────────────────")
        print("Loading model…")

        let embeddingProvider = try await provider.option.makeProvider()
        let benchmark = EmbeddingBenchmark()

        // Run scientific pairs (most domain-relevant) plus general and retrieval pairs
        let testSets: [(name: String, pairs: [TextPair])] = [
            ("Scientific",  EmbeddingBenchmark.scientificPairs),
            ("Retrieval",   EmbeddingBenchmark.retrievalPairs),
            ("General",     EmbeddingBenchmark.generalPairs),
            ("Paraphrase",  EmbeddingBenchmark.paraphrasePairs),
        ]

        for testSet in testSets {
            print("\nRunning '\(testSet.name)' test set (\(testSet.pairs.count) pairs)…")
            let result = await benchmark.runSafe(
                provider: embeddingProvider,
                name: provider.option.displayName,
                pairs: testSet.pairs
            )
            print(result.summary)
        }
    }
}
