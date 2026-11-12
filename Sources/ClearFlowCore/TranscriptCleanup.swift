import Foundation

/// Deterministic, instant cleanup of raw speech-to-text output. It removes speech
/// disfluencies and applies spoken layout commands without rewriting wording.
public enum TranscriptCleanup {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure is a programming error.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
    private static func replace(_ text: String, _ pattern: NSRegularExpression, _ template: String) -> String {
        pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
    // Hesitation sounds only; words such as "like" or "so" often carry meaning.
    private static let filler = regex(#"(?:,\s*)?\b(?:u+m+|u+h+m*|e+r+m+|h+m{2,})\b(?:\s*,)?"#)
    // Stutters. Grammatical or emphatic repeats ("had had", "very very") are kept.
    private static let repeated = regex(#"\b(?!(?:that|had|is|very|really|no|yeah|bye|ha)\b)([a-z']+)(?:\s+\1\b)+"#)
    // Layout commands must stand alone as a sentence, so "a new line of products" is kept.
    private static let command = regex(#"(^|[.!?,;:]|\n)[ \t]*\bnew (line|paragraph)\b[ \t]*[.!?,;:]?(?=\s|$)"#)
    private static let spaceBeforePunctuation = regex(#"[ \t]+([,.!?;:])"#)
    private static let repeatedCommas = regex(#",(?:\s*,)+"#)
    private static let commaBeforeStop = regex(#",\s*([.!?])"#)
    private static let orphanStop = regex(#"([.!?])(?:[ \t]+[.,](?!\d))+"#)
    private static let horizontalSpace = regex(#"[ \t]{2,}"#)
    private static let spaceAroundBreak = regex(#"[ \t]*\n[ \t]*"#)
    private static let removed: Character = "\u{2}"

    public static func clean(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        text = replace(text, command, "$1\u{1}$2\u{1}")
        text = text.replacingOccurrences(of: "\u{1}line\u{1}", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "\u{1}paragraph\u{1}", with: "\n\n", options: .caseInsensitive)
        text = capitalizeAfterRemovals(replace(text, filler, String(removed)))
        text = text.replacingOccurrences(of: String(removed), with: " ")
        text = replace(text, orphanStop, "$1")
        text = replace(text, repeated, "$1")
        text = replace(text, spaceBeforePunctuation, "$1")
        text = replace(text, repeatedCommas, ",")
        text = replace(text, commaBeforeStop, "$1")
        text = replace(text, horizontalSpace, " ")
        text = replace(text, spaceAroundBreak, "\n")
        while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        // A filler removed at the start of a line can leave stray leading punctuation.
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var line = Substring(line)
            while let first = line.first, first == "," || first == " " || (first == "." && line.dropFirst().first == " ") {
                line = line.dropFirst()
            }
            return String(line)
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Capitalizes the first letter of the text and of each line, and a word that
    /// starts a sentence because a filler before it was removed ("Okay. Um, so" →
    /// "Okay. So"). Other capitalization is the speech model's and is left alone.
    static func capitalizeAfterRemovals(_ text: String) -> String {
        var result = ""
        var capitalizeNext = true
        var sentenceStart = true
        for character in text {
            if character == removed {
                if sentenceStart { capitalizeNext = true }
                result.append(character); continue
            }
            if capitalizeNext, character.isLetter {
                result += character.uppercased(); capitalizeNext = false; sentenceStart = false; continue
            }
            result.append(character)
            if character == "\n" { capitalizeNext = true; sentenceStart = true; continue }
            if character.isWhitespace { continue }
            sentenceStart = ".!?".contains(character)
            if character.isLetter || character.isNumber { capitalizeNext = false }
        }
        return result
    }

    /// Adapts cleaned text to the characters around the cursor: spacing, and
    /// continuing a sentence in lowercase without a premature full stop.
    public static func fit(_ text: String, before: String, after: String) -> String {
        guard !text.isEmpty else { return text }
        var text = text
        let previous = before.last
        let previousVisible = before.last { !$0.isWhitespace }
        let following = after.first
        let nextVisible = after.first { !$0.isWhitespace }
        let continuing = previousVisible.map { $0.isLetter || $0.isNumber || ",;".contains($0) } ?? false
        if continuing, !text.contains("\n"), let first = text.split(separator: " ").first,
           first.count > 1 || first != "I", !isProperCased(first) {
            text = first.prefix(1).lowercased() + text.dropFirst()
        }
        if let nextVisible, nextVisible.isLowercase, text.hasSuffix("."), !text.hasSuffix("..") {
            text.removeLast()
        }
        if let previous, !previous.isWhitespace, !"([{\"'“‘/-".contains(previous), !text.hasPrefix("\n") {
            text = " " + text
        }
        if let following, following.isLetter || following.isNumber { text += " " }
        return text
    }
    /// Words such as "I'm", "NASA" or "iPhone" keep their capitalization mid-sentence.
    private static func isProperCased(_ word: Substring) -> Bool {
        let letters = word.filter { $0.isLetter }
        if letters.first == "I", word.count > 1, word.dropFirst().first.map({ "'’".contains($0) }) == true { return true }
        return letters.dropFirst().contains { $0.isUppercase } || !(letters.first?.isUppercase ?? false)
    }
}
