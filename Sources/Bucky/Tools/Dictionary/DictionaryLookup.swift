import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

enum DictionaryLookup {
    static func results(for input: String, limit: Int = 8) -> [DictionaryResult] {
        let term = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }

        var results: [DictionaryResult] = []
        var seenTerms = Set<String>()

        appendResult(for: term, to: &results, seenTerms: &seenTerms)

        for candidate in fuzzyCandidates(for: term) {
            guard results.count < limit else { break }
            appendResult(for: candidate, to: &results, seenTerms: &seenTerms)
        }

        return results
    }

    private static func appendResult(
        for term: String,
        to results: inout [DictionaryResult],
        seenTerms: inout Set<String>
    ) {
        let normalizedTerm = normalized(term)
        guard seenTerms.insert(normalizedTerm).inserted,
              let definition = definition(for: term) else {
            return
        }

        results.append(DictionaryResult(term: term, definition: definition))
    }

    private static func definition(for term: String) -> String? {
        let rangeLength = (term as NSString).length
        guard rangeLength > 0,
              let definition = DCSCopyTextDefinition(
                nil,
                term as CFString,
                CFRange(location: 0, length: rangeLength)
              )?.takeRetainedValue() as String? else {
            return nil
        }

        let trimmedDefinition = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDefinition.isEmpty ? nil : trimmedDefinition
    }

    private static func fuzzyCandidates(for term: String) -> [String] {
        let checker = NSSpellChecker.shared
        let range = NSRange(location: 0, length: (term as NSString).length)
        let completions = checker.completions(
            forPartialWordRange: range,
            in: term,
            language: nil,
            inSpellDocumentWithTag: 0
        ) ?? []
        let guesses = checker.guesses(
            forWordRange: range,
            in: term,
            language: nil,
            inSpellDocumentWithTag: 0
        ) ?? []

        var seen = Set<String>()
        return (completions + guesses)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { candidateScore($0, query: term) > candidateScore($1, query: term) }
            .filter { seen.insert(normalized($0)).inserted }
    }

    private static func candidateScore(_ candidate: String, query: String) -> Int {
        let normalizedCandidate = normalized(candidate)
        let normalizedQuery = normalized(query)

        if normalizedCandidate == normalizedQuery {
            return 10_000
        }
        if normalizedCandidate.hasPrefix(normalizedQuery) {
            return 9_000 - min(normalizedCandidate.count, 500)
        }
        if normalizedCandidate.contains(normalizedQuery) {
            return 7_000 - min(normalizedCandidate.count, 500)
        }

        return 5_000 - min(levenshteinDistance(normalizedCandidate, normalizedQuery), 50) * 80
    }

    private static func levenshteinDistance(_ left: String, _ right: String) -> Int {
        let leftCharacters = Array(left)
        let rightCharacters = Array(right)

        guard !leftCharacters.isEmpty else { return rightCharacters.count }
        guard !rightCharacters.isEmpty else { return leftCharacters.count }

        var previous = Array(0...rightCharacters.count)
        var current = Array(repeating: 0, count: rightCharacters.count + 1)

        for (leftIndex, leftCharacter) in leftCharacters.enumerated() {
            current[0] = leftIndex + 1

            for (rightIndex, rightCharacter) in rightCharacters.enumerated() {
                let substitutionCost = leftCharacter == rightCharacter ? 0 : 1
                current[rightIndex + 1] = min(
                    previous[rightIndex + 1] + 1,
                    current[rightIndex] + 1,
                    previous[rightIndex] + substitutionCost
                )
            }

            swap(&previous, &current)
        }

        return previous[rightCharacters.count]
    }
}
