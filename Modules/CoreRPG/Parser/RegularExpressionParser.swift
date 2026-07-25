// @copyright André Trettin

import Foundation
import Synchronization

public enum RegularExpressionParser {
    private static let cache = Mutex<[String: NSRegularExpression]>([:])

    public static func parse(_ line: String, with pattern: String, extract components: [String]) -> [String] {
        guard let regex = regularExpression(for: pattern) else {
            assertionFailure("Cannot initialize Regex")
            return []
        }
        let nsrange = NSRange(line.startIndex ..< line.endIndex, in: line)
        var result: [String] = []

        regex.enumerateMatches(in: line, options: [], range: nsrange) { match, _, _ in
            guard let match else { return }

            for component in components {
                let nsrange = match.range(withName: component)
                if nsrange.location != NSNotFound, let range = Range(nsrange, in: line) {
                    result.append(String(line[range]))
                } else {
                    result.append("")
                }
            }
        }
        return result
    }

    private static func regularExpression(for pattern: String) -> NSRegularExpression? {
        cache.withLock { cache in
            if let cached = cache[pattern] {
                return cached
            }

            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return nil
            }
            cache[pattern] = regex
            return regex
        }
    }
}
