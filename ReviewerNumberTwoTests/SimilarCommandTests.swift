//
//  SimilarCommandTests.swift
//  ReviewerNumberTwoTests
//
//  Tests for SimilarCommand's two static helpers:
//  findPaper (corpus lookup by filename / DOI / label) and meanTopN.
//

import Testing
import Linguistics

// MARK: - findPaper

@Test func findPaperExactFilename() {
    let corpora = [makeCorpus(filename: "Smith2021.md"), makeCorpus(filename: "Jones2019.md")]
    let found = SimilarCommand.findPaper(in: corpora, matching: "Smith2021.md")
    #expect(found?.metadata["filename"] == "Smith2021.md")
}

@Test func findPaperFilenamePrefix() {
    let corpora = [makeCorpus(filename: "Smith2021.md"), makeCorpus(filename: "Jones2019.md")]
    let found = SimilarCommand.findPaper(in: corpora, matching: "Smith2021")
    #expect(found?.metadata["filename"] == "Smith2021.md")
}

@Test func findPaperDOI() {
    let corpora = [makeCorpus(filename: "a.md", doi: "10.1111/abc.123")]
    #expect(SimilarCommand.findPaper(in: corpora, matching: "10.1111/abc.123") != nil)
}

@Test func findPaperLabel() {
    let corpus = Corpus(label: "Population Structure in Oaks", metadata: [:], embeddings: [])
    #expect(SimilarCommand.findPaper(in: [corpus], matching: "Population Structure in Oaks") != nil)
}

@Test func findPaperNoMatch() {
    let corpora = [makeCorpus(filename: "Smith2021.md")]
    #expect(SimilarCommand.findPaper(in: corpora, matching: "NotThere.md") == nil)
}

@Test func findPaperEmptyCorpus() {
    #expect(SimilarCommand.findPaper(in: [], matching: "anything") == nil)
}

@Test func findPaperPrefixAmbiguityReturnsFirst() {
    // Two papers whose filenames share a prefix: first in corpus order wins.
    let corpora = [makeCorpus(filename: "Smith2021a.md"), makeCorpus(filename: "Smith2021b.md")]
    let found = SimilarCommand.findPaper(in: corpora, matching: "Smith2021")
    #expect(found?.metadata["filename"] == "Smith2021a.md")
}

// MARK: - meanTopN

@Test func meanTopNMoreThanN() {
    // 5 scores, n=3 → average of top 3 (0.9, 0.8, 0.7), not all five
    let scores = [0.5, 0.9, 0.3, 0.8, 0.7]
    let result = SimilarCommand.meanTopN(scores, n: 3)
    #expect(abs(result - (0.9 + 0.8 + 0.7) / 3.0) < 1e-10)
}

@Test func meanTopNFewerThanN() {
    // Only 2 scores available, n=3 → average of both
    let result = SimilarCommand.meanTopN([0.6, 0.4], n: 3)
    #expect(abs(result - 0.5) < 1e-10)
}

@Test func meanTopNExactlyN() {
    let result = SimilarCommand.meanTopN([0.9, 0.5, 0.1], n: 3)
    #expect(abs(result - (0.9 + 0.5 + 0.1) / 3.0) < 1e-10)
}

@Test func meanTopNSingleScore() {
    #expect(abs(SimilarCommand.meanTopN([0.75], n: 3) - 0.75) < 1e-10)
}

@Test func meanTopNEmpty() {
    #expect(SimilarCommand.meanTopN([], n: 3) == 0.0)
}

@Test func meanTopNTakesHighestNotFirst() {
    // Input deliberately unsorted: n=2 must pick the two highest values
    let result = SimilarCommand.meanTopN([0.1, 0.9, 0.8], n: 2)
    #expect(abs(result - (0.9 + 0.8) / 2.0) < 1e-10)
}
