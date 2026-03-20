//
//  SimilarCommand.swift
//  ReviewerNumberTwo
//
//  Finds the most similar papers to a given paper using section-level embeddings.
//  Similarity is scored as the mean of the top-3 cross-section cosine similarities
//  (max-pooling over section pairs), which captures topical overlap without requiring
//  identical section structures across papers.
//

import ArgumentParser
import Foundation
import Linguistics
import MatrixStuff

struct SimilarCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "similar",
        abstract: "Find papers most similar to a given paper in the corpus."
    )

    @Option(name: .long, help: "Path to SQLite database.")
    var db: String

    @Option(name: .long, help: "Target paper: filename (e.g. 2001_Dyer_Sork_ME.md) or DOI.")
    var paper: String

    @Option(name: .long, help: "Number of similar papers to return (default: 5).")
    var topK: Int = 5

    @Option(name: .long, help: "Embedding provider: nl, miniLM, bgeBase (default), bgeLarge, mxbaiEmbedLarge, fdl, qwen3, nomic.")
    var provider: ProviderArgument = .bgeBase

    func run() async throws {
        let dbURL = URL(fileURLWithPath: db)
        let store = try CorpusStore(url: dbURL)
        let allCorpora = try store.readAll()

        guard !allCorpora.isEmpty else {
            print("Corpus is empty. Run 'ingest' first.")
            return
        }

        // Locate target paper by filename or DOI
        guard let target = allCorpora.first(where: { corpus in
            corpus.metadata["filename"] == paper
                || corpus.metadata["filename"]?.hasPrefix(paper) == true
                || corpus.metadata["doi"] == paper
                || corpus.label == paper
        }) else {
            print("Paper '\(paper)' not found in corpus.")
            print("Available: \(allCorpora.map { $0.metadata["filename"] ?? $0.label }.joined(separator: ", "))")
            return
        }

        let targetEmbeddings = target.embeddings.filter { $0.provider == provider.option }
        guard !targetEmbeddings.isEmpty else {
            print("No '\(provider.rawValue)' embeddings for '\(target.label)'. Re-ingest with --provider \(provider.rawValue).")
            return
        }

        // Score each other paper
        let isFDL = provider == .fdl
        var paperScores: [(corpus: Corpus, score: Double)] = []

        for other in allCorpora where other.id != target.id {
            let otherEmbeddings = other.embeddings.filter { $0.provider == provider.option }
            guard !otherEmbeddings.isEmpty else { continue }

            // Collect all pairwise cosine similarities
            var pairScores: [Double] = []
            for te in targetEmbeddings {
                let tv = isFDL ? te.vector.normal : te.vector
                for oe in otherEmbeddings {
                    let ov = isFDL ? oe.vector.normal : oe.vector
                    pairScores.append(tv .* ov)
                }
            }

            // Mean of top-3 (or all if fewer) as the paper-level score
            pairScores.sort(by: >)
            let topN = min(3, pairScores.count)
            let score = pairScores.prefix(topN).reduce(0.0, +) / Double(topN)
            paperScores.append((other, score))
        }

        let results = paperScores.sorted { $0.score > $1.score }.prefix(topK)

        print("\nTop \(results.count) paper(s) similar to: \"\(target.label)\"\n")
        for (i, entry) in results.enumerated() {
            let filename = entry.corpus.metadata["filename"] ?? "—"
            let doi = entry.corpus.metadata["doi"].map { "DOI: \($0)" } ?? ""
            print("[\(i + 1)] \(entry.corpus.label)")
            print("    File  : \(filename)  \(doi)")
            print("    Score : \(String(format: "%.4f", entry.score))")
            print()
        }
    }
}
