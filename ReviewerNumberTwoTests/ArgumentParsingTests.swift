//
//  ArgumentParsingTests.swift
//  ReviewerNumberTwoTests
//
//  Tests for CLI argument types: ProviderArgument → EmbeddingProviderOption mapping,
//  ManuscriptParts case-insensitive parsing, and EmbeddingGranularity parsing.
//

import Testing
import ArgumentParser
import Linguistics

// MARK: - ProviderArgument

@Test func providerArgumentAllCasesMapToCorrectOption() {
    let expected: [(ProviderArgument, EmbeddingProviderOption)] = [
        (.nl,              .nlEmbedding),
        (.fdl,             .fdlEmbedding),
        (.miniLM,          .miniLM),
        (.bgeBase,         .bgeBase),
        (.bgeLarge,        .bgeLarge),
        (.mxbaiEmbedLarge, .mxbaiEmbedLarge),
        (.qwen3,           .qwen3Embedding),
        (.nomic,           .nomicTextV1_5),
    ]
    for (arg, option) in expected {
        #expect(arg.option == option, "\(arg.rawValue) should map to \(option)")
    }
}

@Test func providerArgumentRawValueParsing() {
    for arg in ProviderArgument.allCases {
        #expect(ProviderArgument(rawValue: arg.rawValue) == arg)
    }
    #expect(ProviderArgument(rawValue: "BGEBASE") == nil)
    #expect(ProviderArgument(rawValue: "invalid") == nil)
    #expect(ProviderArgument(rawValue: "") == nil)
}

// MARK: - ManuscriptParts

@Test func manuscriptPartsAllCasesParseExact() {
    for part in ManuscriptParts.allCases {
        #expect(ManuscriptParts(argument: part.rawValue) == part,
                "\(part.rawValue) should parse to itself")
    }
}

@Test func manuscriptPartsCaseInsensitive() {
    #expect(ManuscriptParts(argument: "introduction") == .Introduction)
    #expect(ManuscriptParts(argument: "INTRODUCTION") == .Introduction)
    #expect(ManuscriptParts(argument: "Introduction") == .Introduction)
    #expect(ManuscriptParts(argument: "methods")      == .Methods)
    #expect(ManuscriptParts(argument: "METHODS")      == .Methods)
    #expect(ManuscriptParts(argument: "results")      == .Results)
    #expect(ManuscriptParts(argument: "discussion")   == .Discussion)
    #expect(ManuscriptParts(argument: "abstract")     == .Abstract)
    #expect(ManuscriptParts(argument: "title")        == .Title)
    #expect(ManuscriptParts(argument: "other")        == .Other)
}

@Test func manuscriptPartsInvalidInput() {
    #expect(ManuscriptParts(argument: "intro")         == nil)
    #expect(ManuscriptParts(argument: "meth")          == nil)
    #expect(ManuscriptParts(argument: "Introduction2") == nil)
    #expect(ManuscriptParts(argument: "")              == nil)
    #expect(ManuscriptParts(argument: " Introduction") == nil)
}

// MARK: - EmbeddingGranularity

@Test func embeddingGranularityParsing() {
    #expect(EmbeddingGranularity(argument: "section")              == .section)
    #expect(EmbeddingGranularity(argument: "paragraph")            == .paragraph)
    #expect(EmbeddingGranularity(argument: "sectionAndParagraphs") == .sectionAndParagraphs)
}

@Test func embeddingGranularityInvalidInput() {
    #expect(EmbeddingGranularity(argument: "Section")               == nil)
    #expect(EmbeddingGranularity(argument: "sections")              == nil)
    #expect(EmbeddingGranularity(argument: "sectionandparagraphs")  == nil)
    #expect(EmbeddingGranularity(argument: "")                      == nil)
}
