//
//  IngestCommandTests.swift
//  ReviewerNumberTwoTests
//
//  Tests for IngestCommand's three static helpers:
//  parseProviders, filterNew, and progressLine.
//

import Testing
import Linguistics

// MARK: - parseProviders

@Test func parseProvidersBasic() {
    let result = IngestCommand.parseProviders("fdl,nl,bgeBase")
    #expect(result.map(\.rawValue) == ["fdl", "nl", "bgeBase"])
}

@Test func parseProvidersWhitespaceTrimmed() {
    let result = IngestCommand.parseProviders("fdl, nl , bgeBase")
    #expect(result.map(\.rawValue) == ["fdl", "nl", "bgeBase"])
}

@Test func parseProvidersSingle() {
    let result = IngestCommand.parseProviders("bgeBase")
    #expect(result == [.bgeBase])
}

@Test func parseProvidersEmptyString() {
    #expect(IngestCommand.parseProviders("").isEmpty)
}

@Test func parseProvidersDropsUnrecognisedTokens() {
    // Unknown tokens are silently dropped; known tokens survive in order.
    let result = IngestCommand.parseProviders("bgeBase,TYPO,nl")
    #expect(result.map(\.rawValue) == ["bgeBase", "nl"])
}

@Test func parseProvidersAllUnrecognised() {
    #expect(IngestCommand.parseProviders("foo,bar,baz").isEmpty)
}

// MARK: - filterNew

@Test func filterNewKeepsUnseenCorpora() {
    let corpora = [makeCorpus(filename: "a.md"), makeCorpus(filename: "b.md")]
    let result = IngestCommand.filterNew(corpora, existingFilenames: [], existingDOIs: [])
    #expect(result.count == 2)
}

@Test func filterNewExcludesByFilename() {
    let corpora = [makeCorpus(filename: "a.md"), makeCorpus(filename: "b.md")]
    let result = IngestCommand.filterNew(corpora, existingFilenames: ["a.md"], existingDOIs: [])
    #expect(result.count == 1)
    #expect(result[0].metadata["filename"] == "b.md")
}

@Test func filterNewExcludesByDOI() {
    let corpora = [makeCorpus(filename: "a.md", doi: "10.1234/abc"),
                   makeCorpus(filename: "b.md")]
    let result = IngestCommand.filterNew(corpora, existingFilenames: [], existingDOIs: ["10.1234/abc"])
    #expect(result.count == 1)
    #expect(result[0].metadata["filename"] == "b.md")
}

@Test func filterNewEmptyDOINotMatchedByDOISet() {
    // A corpus whose DOI is the empty string must never be excluded by DOI lookup.
    let corpus = Corpus(label: "x", metadata: ["filename": "x.md", "doi": ""], embeddings: [])
    let result = IngestCommand.filterNew([corpus], existingFilenames: [], existingDOIs: [""])
    #expect(result.count == 1, "Empty DOI must not match the existingDOIs set")
}

@Test func filterNewMixedBatch() {
    let corpora = [
        makeCorpus(filename: "a.md", doi: "10.1/a"),
        makeCorpus(filename: "b.md"),
        makeCorpus(filename: "c.md", doi: "10.1/c"),
        makeCorpus(filename: "d.md"),
    ]
    let result = IngestCommand.filterNew(corpora,
                                         existingFilenames: ["b.md"],
                                         existingDOIs: ["10.1/a"])
    #expect(result.count == 2)
    let filenames = Set(result.compactMap { $0.metadata["filename"] })
    #expect(filenames == ["c.md", "d.md"])
}

// MARK: - progressLine

@Test func progressLineTotalZeroReturnsNil() {
    #expect(IngestCommand.progressLine(completed: 0, total: 0, filename: "x.md") == nil)
}

@Test func progressLineFullyComplete() throws {
    let line = try #require(IngestCommand.progressLine(completed: 5, total: 5, filename: "x.md"))
    #expect(line.contains("100%"))
    #expect(line.contains("5/5"))
    #expect(line.contains("x.md"))
    #expect(line.contains(String(repeating: "█", count: 20)))
    #expect(!line.contains("░"))
}

@Test func progressLineZeroCompleted() throws {
    let line = try #require(IngestCommand.progressLine(completed: 0, total: 10, filename: "x.md"))
    #expect(line.contains("0%"))
    #expect(line.contains("0/10"))
    #expect(line.contains(String(repeating: "░", count: 20)))
    #expect(!line.contains("█"))
}

@Test func progressLineHalfway() throws {
    let line = try #require(IngestCommand.progressLine(completed: 1, total: 2, filename: "test.md"))
    #expect(line.contains("50%"))
    #expect(line.contains("1/2"))
    #expect(line.contains("test.md"))
}

@Test func progressLineFilenameIncluded() throws {
    let line = try #require(IngestCommand.progressLine(completed: 3, total: 10, filename: "Dyer2001.md"))
    #expect(line.contains("Dyer2001.md"))
}
