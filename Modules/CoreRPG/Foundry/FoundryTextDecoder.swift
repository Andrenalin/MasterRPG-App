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

        let substitutions = [
            (#"(?is)<!--.*?-->"#, ""),
            (#"(?is)<\s*(script|style|template|noscript)\b[^>]*>.*?<\s*/\s*\1\s*>"#, ""),
            (#"(?i)<\s*(?:br|hr)\b[^>]*>"#, "\n"),
            (
                #"(?i)<\s*/\s*(?:address|article|aside|blockquote|dd|div|dl|dt|fieldset|figcaption|figure|footer|form|h[1-6]|header|li|main|nav|ol|p|pre|section|table|tbody|td|tfoot|th|thead|tr|ul)\s*>"#,
                "\n\n"
            ),
            (#"(?is)<\s*/?\s*[A-Za-z][^>]*>"#, ""),
        ]
        for (pattern, replacement) in substitutions {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            source = expression.stringByReplacingMatches(
                in: source,
                range: range,
                withTemplate: replacement
            )
        }

        return normalizedParagraphs(in: decodedText(source))
    }
}

private extension FoundryTextDecoder {
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
                  let semicolon = source[current...].firstIndex(of: ";"),
                  source.distance(from: current, to: semicolon) <= 34 else {
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
