//
//  TestSupport.swift
//  ReviewerNumberTwoTests
//
//  Shared helpers available to every test file in this target.
//

import Linguistics
import Foundation

/// Builds a minimal Corpus with no embeddings, suitable for lookup and filter tests.
func makeCorpus(filename: String, doi: String = "", label: String? = nil) -> Corpus {
    var meta: [String: String] = ["filename": filename]
    if !doi.isEmpty { meta["doi"] = doi }
    return Corpus(label: label ?? filename, metadata: meta, embeddings: [])
}

/// URL of the Fixtures directory sitting next to this source file.
var fixtureDirectory: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
}
