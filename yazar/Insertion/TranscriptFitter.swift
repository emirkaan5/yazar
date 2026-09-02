import Foundation

/// Fits an already-formatted transcript to the text around its insertion point.
nonisolated enum TranscriptFitter {
    private static let boundaryBridges = Set<Character>("—`,-/:;()[]{} ")
    private static let precedingPunctuation = Set<Character>("!%),.:;>?]}")
    private static let continuingAfterPunctuation = Set<Character>("!%,.:;>?")
    private static let operators = Set<Character>("\\/|-&*+=~")
    private static let removableTerminalPunctuation = Set<Character>("!.?")
    private static let eastAsianTerminalPunctuation = Set<Character>(
        "。、，．！？；：…‥「」『』（）〔〕【】《》〈〉〝〞〟・"
    )

    /// Applies the local rules in their defined order.
    static func fit(_ transcript: String, to context: TextInsertionContext) -> String {
        guard !transcript.isEmpty else { return transcript }

        var output = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let lineBefore = currentLineBefore(in: context.beforeText)
        let lineAfter = currentLineAfter(in: context.afterText)

        if !context.selectedText.isEmpty {
            let trimmedSelection = String(
                context.selectedText.drop(while: \.isWhitespace)
            )

            if let first = trimmedSelection.first,
               isLetter(first),
               first.lowercased() == String(first) {
                output = lowercasingFirstCharacter(of: output)
            }

            if !(trimmedSelection.last.map(precedingPunctuation.contains) ?? false) {
                removeTerminalPunctuation(from: &output)
            }

            if context.selectedText.first == " " {
                output.insert(" ", at: output.startIndex)
            }
            if context.selectedText.last == " " {
                output.append(" ")
            }
            return output
        }

        if isContinuingBefore(lineBefore) {
            output = lowercasingFirstCharacter(of: output)
        }

        if isContinuingAfter(lineAfter) {
            removeTerminalPunctuation(from: &output)
        }

        if shouldAddLeadingSpace(to: lineBefore) {
            output.insert(" ", at: output.startIndex)
        }

        if !(output.last.map(eastAsianTerminalPunctuation.contains) ?? false),
           shouldAddTrailingSpace(before: lineAfter) {
            output.append(" ")
        }

        return output
    }

    private static func currentLineBefore(in text: String) -> String {
        guard let newline = text.lastIndex(of: "\n") else { return text }
        return String(text[text.index(after: newline)...])
    }

    private static func currentLineAfter(in text: String) -> String {
        guard let newline = text.firstIndex(of: "\n") else { return text }
        return String(text[..<newline])
    }

    private static func isContinuingBefore(_ lineBefore: String) -> Bool {
        var trimmed = lineBefore[...]
        while let last = trimmed.last, isBoundaryWhitespace(last) {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty else { return false }

        for character in trimmed.reversed() {
            if isAlphanumeric(character) { return true }
            if !boundaryBridges.contains(character) { return false }
        }
        return false
    }

    private static func isContinuingAfter(_ lineAfter: String) -> Bool {
        let trimmed = lineAfter.drop(while: isBoundaryWhitespace)
        guard !trimmed.isEmpty else { return false }

        for character in trimmed {
            if isLetter(character), character.lowercased() == String(character) {
                return true
            }
            if continuingAfterPunctuation.contains(character) { return true }
            if !boundaryBridges.contains(character) { return false }
        }
        return false
    }

    private static func shouldAddLeadingSpace(to lineBefore: String) -> Bool {
        guard let finalCharacter = lineBefore.last else { return false }
        if belongsToUnspacedScript(finalCharacter) { return false }
        if isAlphanumeric(finalCharacter) { return true }
        if precedingPunctuation.contains(finalCharacter) { return true }
        guard operators.contains(finalCharacter) else { return false }
        if lineBefore.count == 1 { return true }
        return lineBefore.dropLast().last == " "
    }

    private static func shouldAddTrailingSpace(before lineAfter: String) -> Bool {
        guard let first = lineAfter.first else { return true }
        if isAlphanumeric(first) { return true }
        guard operators.contains(first) else { return false }
        let secondIndex = lineAfter.index(after: lineAfter.startIndex)
        return secondIndex < lineAfter.endIndex && lineAfter[secondIndex] == " "
    }

    private static func lowercasingFirstCharacter(of text: String) -> String {
        guard text.count > 1, let first = text.first else { return text }
        return first.lowercased() + String(text.dropFirst())
    }

    private static func removeTerminalPunctuation(from text: inout String) {
        while let last = text.last, removableTerminalPunctuation.contains(last) {
            text.removeLast()
        }
    }

    private static func isBoundaryWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\u{00A0}"
    }

    private static func isAlphanumeric(_ character: Character) -> Bool {
        isLetter(character) || isNumber(character)
    }

    // Not `Character.isLetter`/`isNumber`: those use the Unicode Alphabetic
    // property, which classifies 1,059 more BMP scalars as letters, including
    // Indic vowel signs and circled letters. These rules were verified against
    // general categories, so they ask for those.
    private static func isLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
                 .modifierLetter, .otherLetter:
                true
            default:
                false
            }
        }
    }

    private static func isNumber(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .decimalNumber, .letterNumber, .otherNumber:
                true
            default:
                false
            }
        }
    }

    /// Han, Hiragana, and Katakana do not separate words with spaces, so a
    /// fitted transcript must not gain a leading one.
    private static func belongsToUnspacedScript(_ character: Character) -> Bool {
        String(character).wholeMatch(
            of: /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]/
        ) != nil
    }
}
