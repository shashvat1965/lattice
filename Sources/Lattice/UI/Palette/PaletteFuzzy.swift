import Foundation

/// Case-insensitive subsequence matching for the command palette.
///
/// Returns the score that ranks a candidate *and* the character offsets that
/// matched, so the row can accent exactly the letters the user typed.
struct PaletteMatch {
    let score: Int
    let indices: [Int]
}

enum PaletteFuzzy {

    static func match(query: String, in candidate: String) -> PaletteMatch? {
        let needle = Array(query.lowercased())
        guard !needle.isEmpty else { return PaletteMatch(score: 0, indices: []) }

        let text = Array(candidate)
        let lowered = text.map { Character($0.lowercased()) }
        guard text.count >= needle.count else { return nil }

        var indices: [Int] = []
        var score = 0
        var cursor = 0
        var previous = -2

        for index in 0..<text.count {
            guard cursor < needle.count else { break }
            guard lowered[index] == needle[cursor] else { continue }

            indices.append(index)
            score += 1

            if index == previous + 1 {
                score += 6                                  // typed characters land together
            } else if index == 0 {
                score += 9                                  // match starts the title
            } else {
                let before = text[index - 1]
                if before == " " || before == "-" || before == "_" || before == "/" || before == "." {
                    score += 7                              // start of a word
                } else if before.isLowercase && text[index].isUppercase {
                    score += 5                              // camelCase boundary
                } else {
                    score -= min(index - previous - 1, 4)   // long gaps are weaker
                }
            }

            previous = index
            cursor += 1
        }

        guard cursor == needle.count else { return nil }

        // Short candidates that contain everything rank above sprawling ones.
        score += max(0, 14 - text.count / 3)
        if candidate.lowercased().hasPrefix(query.lowercased()) { score += 22 }

        return PaletteMatch(score: score, indices: indices)
    }
}
