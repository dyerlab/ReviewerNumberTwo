//
//  SearchCommandTests.swift
//  ReviewerNumberTwoTests
//
//  Tests for SearchCommand.rerankerCandidateCount: the topK×5 clamping logic
//  that controls how many candidates reach the cross-encoder reranker.
//

import Testing

@Test func rerankerCandidateCountNormal() {
    #expect(SearchCommand.rerankerCandidateCount(topK: 10, available: 200) == 50)
}

@Test func rerankerCandidateCountClampedToAvailable() {
    #expect(SearchCommand.rerankerCandidateCount(topK: 10, available: 30) == 30)
}

@Test func rerankerCandidateCountExactlyTopKTimes5() {
    #expect(SearchCommand.rerankerCandidateCount(topK: 10, available: 50) == 50)
}

@Test func rerankerCandidateCountSmallTopK() {
    #expect(SearchCommand.rerankerCandidateCount(topK: 1, available: 100) == 5)
    #expect(SearchCommand.rerankerCandidateCount(topK: 1, available: 3)   == 3)
}

@Test func rerankerCandidateCountAvailableSmallerThanTopK() {
    #expect(SearchCommand.rerankerCandidateCount(topK: 10, available: 2) == 2)
}
