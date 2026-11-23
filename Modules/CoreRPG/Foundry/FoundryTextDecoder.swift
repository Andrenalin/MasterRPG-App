// @copyright André Trettin

import Foundation

/// Converts Foundry-authored HTML and escaped text into safe, user-visible plain text.
///
/// Foundry content can contain HTML tags, named or numeric HTML entities, and JSON strings
/// containing control characters. Keeping that cleanup at the import boundary prevents escaped
/// text such as `&auml;` or `&#x2014;` from leaking into editors and viewers.
public enum FoundryTextDecoder {
    /// Decodes HTML entities and normalizes control characters without removing markup.
    ///
    /// Use this for scalar values that may legitimately contain comparison characters or other
    /// text that merely resembles HTML. Use ``plainText(fromHTML:)`` for an HTML field.
    public static func decodedText(_ source: String) -> String {
        normalizeControls(in: decodeEntities(in: source))
    }

    /// Removes non-visible HTML content and markup, then decodes the remaining visible text.
    public static func plainText(fromHTML source: String?) -> String {
        guard var source, !source.isEmpty else { return "" }

        // The two lazy patterns (comments, script-like blocks) scanned to the end of the text for
        // every unterminated opener, which is quadratic; the linear scanner below looks for each
        // closer at most once per name. The other patterns are compiled once. See
        // CODE_AUDIT_26 §7.4.
        source = removingNonVisibleBlocks(from: source)
        source = strippingTags(from: source)

        return normalizedParagraphs(in: decodedText(source))
    }
}

private extension FoundryTextDecoder {
    static let blockElementNames: Set<String> = [
        "address", "article", "aside", "blockquote", "dd", "div", "dl", "dt", "fieldset", "figcaption",
        "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "li", "main", "nav",
        "ol", "p", "pre", "section", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul",
    ]

    /// Replaces `<br>`/`<hr>` by a line break, the end of a block element by a paragraph break
    /// and removes every other tag, in one linear pass over the UTF-8 bytes. The regular
    /// expressions this replaces (`<\s*/?\s*[A-Za-z][^>]*>`) scanned to the end of the text for
    /// every `<` that has no `>` after it, which is quadratic: a crafted description froze the
    /// import for minutes. Once a `<` finds no `>`, no later one can. See CODE_AUDIT_28 §6.3.
    static func strippingTags(from source: String) -> String {
        let bytes = Array(source.utf8)
        guard bytes.contains(UInt8(ascii: "<")) else { return source }
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var hasNoCloserAhead = false
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            guard byte == UInt8(ascii: "<"), !hasNoCloserAhead else {
                output.append(byte)
                index += 1
                continue
            }
            var cursor = skippingWhitespace(in: bytes, from: index + 1)
            let isClosing = cursor < bytes.count && bytes[cursor] == UInt8(ascii: "/")
            if isClosing { cursor = skippingWhitespace(in: bytes, from: cursor + 1) }
            let nameStart = cursor
            guard cursor < bytes.count, isASCIILetter(bytes[cursor]) else {
                output.append(byte)
                index += 1
                continue
            }
            guard let close = bytes[cursor...].firstIndex(of: UInt8(ascii: ">")) else {
                hasNoCloserAhead = true
                output.append(byte)
                index += 1
                continue
            }
            while cursor < close, isASCIILetter(bytes[cursor]) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[cursor]) {
                cursor += 1
            }
            let name = String(decoding: bytes[nameStart..<cursor].map(lowercased), as: UTF8.self)
            let rest = bytes[cursor..<close]
            if !isClosing, name == "br" || name == "hr", !isWordByte(bytes, at: cursor) {
                output.append(UInt8(ascii: "\n"))
            } else if isClosing, blockElementNames.contains(name), rest.allSatisfy({ [0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D].contains($0) }) {
                output.append(contentsOf: [UInt8(ascii: "\n"), UInt8(ascii: "\n")])
            }
            index = close + 1
        }
        return String(decoding: output, as: UTF8.self)
    }

    static func isASCIILetter(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(lowercased(byte))
    }

    static let invisibleBlockNames: [[UInt8]] = ["script", "style", "template", "noscript"].map { Array($0.utf8) }

    /// Removes `<!-- ... -->` comments and `<script|style|template|noscript> ... </...>` blocks
    /// (the same text the former `(?is)` patterns removed), in one pass over the UTF-8 bytes. An
    /// opener without a closer stays in the text, as before.
    static func removingNonVisibleBlocks(from source: String) -> String {
        let bytes = Array(source.utf8)
        guard bytes.contains(UInt8(ascii: "<")) else { return source }
        let withoutComments = removingComments(from: bytes)
        let result = removingInvisibleElements(from: withoutComments)
        return String(decoding: result, as: UTF8.self)
    }

    static func removingComments(from bytes: [UInt8]) -> [UInt8] {
        let opener = Array("<!--".utf8)
        let closer = Array("-->".utf8)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0
        var hasNoCloserAhead = false
        while index < bytes.count {
            if !hasNoCloserAhead, matches(opener, in: bytes, at: index) {
                if let end = firstIndex(of: closer, in: bytes, from: index + opener.count) {
                    index = end + closer.count
                    continue
                }
                // No closer after this opener means none after any later one either.
                hasNoCloserAhead = true
            }
            output.append(bytes[index])
            index += 1
        }
        return output
    }

    static func removingInvisibleElements(from bytes: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        // Names whose closer was searched for and not found: a later opener of the same name
        // cannot find one either.
        var exhaustedNames: Set<Int> = []
        var index = 0
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "<"),
               let opener = invisibleOpener(in: bytes, at: index),
               !exhaustedNames.contains(opener.nameIndex) {
                if let end = closerEnd(of: opener.nameIndex, in: bytes, from: opener.end) {
                    index = end
                    continue
                }
                exhaustedNames.insert(opener.nameIndex)
            }
            output.append(bytes[index])
            index += 1
        }
        return output
    }

    /// `<\s*name\b[^>]*>` at `start`: the index in `invisibleBlockNames` and the index after `>`.
    static func invisibleOpener(in bytes: [UInt8], at start: Int) -> (nameIndex: Int, end: Int)? {
        var index = skippingWhitespace(in: bytes, from: start + 1)
        guard let nameIndex = matchedName(in: bytes, at: index) else { return nil }
        index += invisibleBlockNames[nameIndex].count
        guard !isWordByte(bytes, at: index),
              let close = bytes[index...].firstIndex(of: UInt8(ascii: ">")) else { return nil }
        return (nameIndex, close + 1)
    }

    /// The end of the first `<\s*/\s*name\s*>` at or after `start`.
    static func closerEnd(of nameIndex: Int, in bytes: [UInt8], from start: Int) -> Int? {
        let name = invisibleBlockNames[nameIndex]
        var index = start
        while index < bytes.count, let lessThan = bytes[index...].firstIndex(of: UInt8(ascii: "<")) {
            var cursor = skippingWhitespace(in: bytes, from: lessThan + 1)
            if cursor < bytes.count, bytes[cursor] == UInt8(ascii: "/") {
                cursor = skippingWhitespace(in: bytes, from: cursor + 1)
                if matchedName(in: bytes, at: cursor) == nameIndex {
                    cursor = skippingWhitespace(in: bytes, from: cursor + name.count)
                    if cursor < bytes.count, bytes[cursor] == UInt8(ascii: ">") { return cursor + 1 }
                }
            }
            index = lessThan + 1
        }
        return nil
    }

    static func matchedName(in bytes: [UInt8], at index: Int) -> Int? {
        invisibleBlockNames.firstIndex { name in
            guard index + name.count <= bytes.count else { return false }
            return zip(name, bytes[index..<(index + name.count)]).allSatisfy { $0 == lowercased($1) }
        }
    }

    static func lowercased(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
    }

    static func isWordByte(_ bytes: [UInt8], at index: Int) -> Bool {
        guard index < bytes.count else { return false }
        let byte = bytes[index]
        return byte == UInt8(ascii: "_")
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
            || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(lowercased(byte))
            || byte >= 0x80
    }

    static func skippingWhitespace(in bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D].contains(bytes[index]) { index += 1 }
        return index
    }

    static func matches(_ pattern: [UInt8], in bytes: [UInt8], at index: Int) -> Bool {
        guard index + pattern.count <= bytes.count else { return false }
        return bytes[index..<(index + pattern.count)].elementsEqual(pattern)
    }

    static func firstIndex(of pattern: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard start + pattern.count <= bytes.count else { return nil }
        var index = start
        while let candidate = bytes[index...].firstIndex(of: pattern[0]) {
            if matches(pattern, in: bytes, at: candidate) { return candidate }
            index = candidate + 1
            if index + pattern.count > bytes.count { return nil }
        }
        return nil
    }

    static let namedEntities: [String: String] = [
        "Tab": "\t",
        "NewLine": "\n",
        "quot": "\"",
        "amp": "&",
        "apos": "'",
        "lt": "<",
        "gt": ">",
        "nbsp": " ",
        "iexcl": "¡",
        "cent": "¢",
        "pound": "£",
        "curren": "¤",
        "yen": "¥",
        "brvbar": "¦",
        "sect": "§",
        "uml": "¨",
        "copy": "©",
        "ordf": "ª",
        "laquo": "«",
        "not": "¬",
        "shy": "\u{00AD}",
        "reg": "®",
        "macr": "¯",
        "deg": "°",
        "plusmn": "±",
        "sup2": "²",
        "sup3": "³",
        "acute": "´",
        "micro": "µ",
        "para": "¶",
        "middot": "·",
        "cedil": "¸",
        "sup1": "¹",
        "ordm": "º",
        "raquo": "»",
        "frac14": "¼",
        "frac12": "½",
        "frac34": "¾",
        "iquest": "¿",
        "Agrave": "À",
        "Aacute": "Á",
        "Acirc": "Â",
        "Atilde": "Ã",
        "Auml": "Ä",
        "Aring": "Å",
        "AElig": "Æ",
        "Ccedil": "Ç",
        "Egrave": "È",
        "Eacute": "É",
        "Ecirc": "Ê",
        "Euml": "Ë",
        "Igrave": "Ì",
        "Iacute": "Í",
        "Icirc": "Î",
        "Iuml": "Ï",
        "ETH": "Ð",
        "Ntilde": "Ñ",
        "Ograve": "Ò",
        "Oacute": "Ó",
        "Ocirc": "Ô",
        "Otilde": "Õ",
        "Ouml": "Ö",
        "times": "×",
        "Oslash": "Ø",
        "Ugrave": "Ù",
        "Uacute": "Ú",
        "Ucirc": "Û",
        "Uuml": "Ü",
        "Yacute": "Ý",
        "THORN": "Þ",
        "szlig": "ß",
        "agrave": "à",
        "aacute": "á",
        "acirc": "â",
        "atilde": "ã",
        "auml": "ä",
        "aring": "å",
        "aelig": "æ",
        "ccedil": "ç",
        "egrave": "è",
        "eacute": "é",
        "ecirc": "ê",
        "euml": "ë",
        "igrave": "ì",
        "iacute": "í",
        "icirc": "î",
        "iuml": "ï",
        "eth": "ð",
        "ntilde": "ñ",
        "ograve": "ò",
        "oacute": "ó",
        "ocirc": "ô",
        "otilde": "õ",
        "ouml": "ö",
        "divide": "÷",
        "oslash": "ø",
        "ugrave": "ù",
        "uacute": "ú",
        "ucirc": "û",
        "uuml": "ü",
        "yacute": "ý",
        "thorn": "þ",
        "yuml": "ÿ",
        "OElig": "Œ",
        "oelig": "œ",
        "Scaron": "Š",
        "scaron": "š",
        "Yuml": "Ÿ",
        "fnof": "ƒ",
        "circ": "ˆ",
        "tilde": "˜",
        "ensp": " ",
        "emsp": " ",
        "thinsp": " ",
        "zwnj": "\u{200C}",
        "zwj": "\u{200D}",
        "lrm": "\u{200E}",
        "rlm": "\u{200F}",
        "ndash": "–",
        "mdash": "—",
        "lsquo": "‘",
        "rsquo": "’",
        "sbquo": "‚",
        "ldquo": "“",
        "rdquo": "”",
        "bdquo": "„",
        "dagger": "†",
        "Dagger": "‡",
        "bull": "•",
        "hellip": "…",
        "permil": "‰",
        "prime": "′",
        "Prime": "″",
        "lsaquo": "‹",
        "rsaquo": "›",
        "oline": "‾",
        "frasl": "⁄",
        "euro": "€",
        "trade": "™",
        "minus": "−",
        "larr": "←",
        "uarr": "↑",
        "rarr": "→",
        "darr": "↓",
        "harr": "↔",
    ]

    /// HTML uses the Windows-1252 replacements for numeric entities in this range.
    static let windows1252NumericEntities: [UInt32: UInt32] = [
        0x80: 0x20AC,
        0x82: 0x201A,
        0x83: 0x0192,
        0x84: 0x201E,
        0x85: 0x2026,
        0x86: 0x2020,
        0x87: 0x2021,
        0x88: 0x02C6,
        0x89: 0x2030,
        0x8A: 0x0160,
        0x8B: 0x2039,
        0x8C: 0x0152,
        0x8E: 0x017D,
        0x91: 0x2018,
        0x92: 0x2019,
        0x93: 0x201C,
        0x94: 0x201D,
        0x95: 0x2022,
        0x96: 0x2013,
        0x97: 0x2014,
        0x98: 0x02DC,
        0x99: 0x2122,
        0x9A: 0x0161,
        0x9B: 0x203A,
        0x9C: 0x0153,
        0x9E: 0x017E,
        0x9F: 0x0178,
    ]

    static func decodeEntities(in source: String) -> String {
        guard source.contains("&") else { return source }

        var output = ""
        output.reserveCapacity(source.count)
        var current = source.startIndex
        while current < source.endIndex {
            guard source[current] == "&",
                  let semicolon = source[current...].prefix(35).firstIndex(of: ";") else {
                output.append(source[current])
                current = source.index(after: current)
                continue
            }

            let bodyStart = source.index(after: current)
            let body = String(source[bodyStart..<semicolon])
            guard let replacement = decodedEntityBody(body) else {
                output.append(contentsOf: source[current...semicolon])
                current = source.index(after: semicolon)
                continue
            }
            output.append(replacement)
            current = source.index(after: semicolon)
        }
        return output
    }

    static func decodedEntityBody(_ body: String) -> String? {
        guard body.first == "#" else { return namedEntities[body] }

        let numericBody = body.dropFirst()
        let isHexadecimal = numericBody.first == "x" || numericBody.first == "X"
        let digits = isHexadecimal ? numericBody.dropFirst() : numericBody
        guard !digits.isEmpty,
              let parsed = UInt32(digits, radix: isHexadecimal ? 16 : 10) else {
            return nil
        }
        let scalarValue = windows1252NumericEntities[parsed] ?? parsed
        guard scalarValue != 0,
              !(0xD800...0xDFFF).contains(scalarValue),
              let scalar = Unicode.Scalar(scalarValue) else {
            return "\u{FFFD}"
        }
        return String(scalar)
    }

    static func normalizeControls(in source: String) -> String {
        var output = ""
        output.reserveCapacity(source.count)
        var previousWasCarriageReturn = false

        for scalar in source.unicodeScalars {
            switch scalar.value {
            case 0x0D:
                output.append("\n")
                previousWasCarriageReturn = true
            case 0x0A:
                if !previousWasCarriageReturn {
                    output.append("\n")
                }
                previousWasCarriageReturn = false
            case 0x09:
                output.append(" ")
                previousWasCarriageReturn = false
            case 0x2028, 0x2029:
                output.append("\n")
                previousWasCarriageReturn = false
            case 0x00...0x08, 0x0B...0x0C, 0x0E...0x1F, 0x7F...0x9F, 0xFEFF, 0x200B:
                previousWasCarriageReturn = false
            case 0xA0:
                output.append(" ")
                previousWasCarriageReturn = false
            default:
                output.unicodeScalars.append(scalar)
                previousWasCarriageReturn = false
            }
        }
        return output
    }

    static func normalizedParagraphs(in source: String) -> String {
        let lines = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var output: [String] = []
        var hasPendingParagraphBreak = false
        for line in lines {
            guard !line.isEmpty else {
                hasPendingParagraphBreak = !output.isEmpty
                continue
            }
            if hasPendingParagraphBreak {
                output.append("")
            }
            output.append(line)
            hasPendingParagraphBreak = false
        }
        return output.joined(separator: "\n")
    }
}
