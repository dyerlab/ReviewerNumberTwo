//
//  ArgumentTypes.swift
//  ReviewerNumberTwo
//
//  CLI argument types for embedding provider, granularity, and manuscript section options.
//

import ArgumentParser
import Linguistics

// MARK: - Provider

enum ProviderArgument: String, CaseIterable, ExpressibleByArgument {
    case nl
    case fdl
    case miniLM
    case bgeBase
    case bgeLarge
    case mxbaiEmbedLarge
    case qwen3
    case nomic

    var option: EmbeddingProviderOption {
        switch self {
        case .nl:              return .nlEmbedding
        case .fdl:             return .fdlEmbedding
        case .miniLM:          return .miniLM
        case .bgeBase:         return .bgeBase
        case .bgeLarge:        return .bgeLarge
        case .mxbaiEmbedLarge: return .mxbaiEmbedLarge
        case .qwen3:           return .qwen3Embedding
        case .nomic:           return .nomicTextV1_5
        }
    }
}

// MARK: - Granularity

extension EmbeddingGranularity: @retroactive ExpressibleByArgument {}

// MARK: - Manuscript section

extension ManuscriptParts: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        let lower = argument.lowercased()
        guard let match = ManuscriptParts.allCases.first(where: { $0.rawValue.lowercased() == lower }) else {
            return nil
        }
        self = match
    }
}
