//
//  AdaptiveSentenceGenerator.swift
//  AksharApp
//
//  Created by iOS SDP Mac54 on 12/05/26.
//

import Foundation
import FoundationModels

final class AdaptiveSentenceGenerator {

    static let shared = AdaptiveSentenceGenerator()

    private init() {}

    func generateSentence(from words: [String]) async throws -> String {
        // 1. Clean and limit to the top 10 most important missed words
        let cleanedWords = Array(Set(words
            .flatMap { $0.components(separatedBy: .whitespacesAndNewlines) }
            .map { $0.trimmingCharacters(in: .punctuationCharacters).lowercased() }
            .filter { word in
                !word.isEmpty &&
                word.count >= 2 &&
                !word.allSatisfy(\.isNumber) &&
                isDictionaryWord(word)
            }))
            .prefix(10)

        // 2. If no usable words remain, use fallback
        guard !cleanedWords.isEmpty else {
            return getSafeDefaultSentence()
        }

        do {
            let prompt = """
            [INST] You are a children's book editor.
            
            WORDS TO USE: \(cleanedWords.joined(separator: ", "))
            
            TASK: 
            Write ONE perfect, meaningful sentence for a 6-year-old.
            
            REQUIREMENTS:
            - You MUST use EVERY word from this list: \(cleanedWords.joined(separator: ", ")).
            - The sentence MUST be grammatically correct and make logical sense.
            - Focus on a simple topic like animals, nature, or playing.
            - No repetition. No lists. Just a single, high-quality sentence.
            - Output ONLY the sentence text.
            [/INST]
            """

            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let generated = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // Basic sanity check
            if !generated.isEmpty && generated.split(separator: " ").count >= 3 {
                return generated
            }
        } catch {
            print("Foundation Model failed: \(error)")
        }

        return getSafeDefaultSentence()
    }

    private func isDictionaryWord(_ word: String) -> Bool {
        // Simple heuristic: words with no vowels (except very short ones like 'my') are likely gibberish
        let vowels = CharacterSet(charactersIn: "aeiouy")
        if word.count > 2 && word.rangeOfCharacter(from: vowels) == nil {
            return false
        }
        return true
    }

    private func getSafeDefaultSentence() -> String {
        let fallbacks = [
            "The sun is very bright today.",
            "I like to play with my friends.",
            "The little dog can run fast.",
            "We can go to the park now.",
            "Look at the big blue sky."
        ]
        return fallbacks.randomElement() ?? "I can read this sentence."
    }
}
