import Foundation

enum CostRates {
    struct ModelRate {
        let inputPer1M: Double
        let outputPer1M: Double
    }

    static let defaultRate = ModelRate(inputPer1M: 3.0, outputPer1M: 15.0)

    static let rates: [String: ModelRate] = [
        // OpenAI Codex
        "gpt-5.3-codex": ModelRate(inputPer1M: 2.50, outputPer1M: 10.0),
        "gpt-4o": ModelRate(inputPer1M: 2.50, outputPer1M: 10.0),
        "gpt-4o-mini": ModelRate(inputPer1M: 0.15, outputPer1M: 0.60),
        "gpt-4-turbo": ModelRate(inputPer1M: 10.0, outputPer1M: 30.0),
        // Claude
        "claude-opus-4": ModelRate(inputPer1M: 15.0, outputPer1M: 75.0),
        "claude-sonnet-4": ModelRate(inputPer1M: 3.0, outputPer1M: 15.0),
        "claude-sonnet-4.5": ModelRate(inputPer1M: 3.0, outputPer1M: 15.0),
        "claude-haiku-4.5": ModelRate(inputPer1M: 0.80, outputPer1M: 4.0),
        "claude-3-5-sonnet": ModelRate(inputPer1M: 3.0, outputPer1M: 15.0),
        "claude-3-5-haiku": ModelRate(inputPer1M: 0.80, outputPer1M: 4.0),
        "claude-3-opus": ModelRate(inputPer1M: 15.0, outputPer1M: 75.0),
    ]

    static func cost(for model: String, inputTokens: Int, outputTokens: Int) -> Double {
        let rate = matchRate(for: model)
        let inputCost = Double(inputTokens) / 1_000_000.0 * rate.inputPer1M
        let outputCost = Double(outputTokens) / 1_000_000.0 * rate.outputPer1M
        return inputCost + outputCost
    }

    private static func matchRate(for model: String) -> ModelRate {
        let lowered = model.lowercased()

        // Exact match
        if let rate = rates[lowered] {
            return rate
        }

        // Fuzzy: find the first key contained in the model string
        for (key, rate) in rates {
            if lowered.contains(key) {
                return rate
            }
        }

        // Reverse: find the first key that contains the model string
        for (key, rate) in rates {
            if key.contains(lowered) {
                return rate
            }
        }

        return defaultRate
    }
}
