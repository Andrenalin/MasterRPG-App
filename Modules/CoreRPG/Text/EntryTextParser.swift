// @copyright André Trettin

import Foundation

/// Parser for converting multi-line text into structured entries
///
/// Format: First line is the title, subsequent lines are content, empty lines separate entries
public struct EntryTextParser {

    public init() {}

    /// Parse multi-line text into name-content pairs
    /// - Parameter text: Multi-line text with entries separated by empty lines
    /// - Returns: Array of tuples containing (name, content) pairs
    public func parse(_ text: String) -> [(name: String, content: String)] {
        var entries: [(name: String, content: String)] = []
        var name = ""
        var content = ""

        normalizeLineEndings(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .forEach { line in
                guard !line.isEmpty else {
                    if !name.isEmpty {
                        entries.append((name: name, content: content.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                    name = ""
                    content = ""
                    return
                }

                if name.isEmpty {
                    name = String(line.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    content.append(contentsOf: "\(line.trimmingCharacters(in: .whitespacesAndNewlines))\n")
                }
            }

        // Add final entry if present
        if !name.isEmpty {
            entries.append((name: name, content: content.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return entries
    }

    /// `text` with `transform` applied to every content line. Title lines (what `parse` takes as an
    /// entry name: the first line of a block with text in it) and empty lines stay as they are,
    /// because a changed name no longer matches its entry on merge and the entry is created anew.
    /// Line endings are normalized as `parse` reads them. See CODE_AUDIT_Since_3.0.1 §5.1.
    public func transformingContent(of text: String, _ transform: (String) -> String) -> String {
        var hasName = false
        return normalizeLineEndings(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                guard !line.isEmpty else {
                    hasName = false
                    return String(line)
                }
                guard hasName else {
                    hasName = !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    return String(line)
                }
                return transform(String(line))
            }
            .joined(separator: "\n")
    }

    /// Remove soft line breaks from text (typically from PDF copies)
    ///
    /// Combines lines within paragraphs while preserving paragraph structure
    /// - Parameter text: Text with potential line breaks mid-paragraph
    /// - Returns: Text with line breaks removed within paragraphs
    public func removeLineBreaks(from text: String) -> String {
        var blocks: [String] = []
        var currentTitle: String = ""
        var currentContent: String = ""

        normalizeLineEndings(text)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .forEach { line in
                if line.isEmpty {
                    if !currentTitle.isEmpty {
                        var block = currentTitle
                        if !currentContent.isEmpty {
                            block.append("\n\(currentContent)")
                        }
                        blocks.append(block)
                    }
                    currentTitle = ""
                    currentContent = ""
                } else {
                    var processedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if currentTitle.isEmpty {
                        currentTitle.append(processedLine)
                    } else {
                        // Handle hyphenated line breaks
                        if processedLine.last == "-" {
                            processedLine = String(processedLine.dropLast())
                        } else {
                            processedLine.append(" ")
                        }
                        currentContent.append(processedLine)
                    }
                }
            }

        // Add final block if present
        if !currentTitle.isEmpty {
            var block = currentTitle
            if !currentContent.isEmpty {
                block.append("\n\(currentContent)")
            }
            blocks.append(block)
        }

        return blocks.joined(separator: "\n\n")
    }

    /// Format entries back to multi-line text
    /// - Parameter entries: Array of (name, content) tuples
    /// - Returns: Formatted multi-line text
    public func format(_ entries: [(name: String, content: String)]) -> String {
        entries.map { entry in
            if entry.content.isEmpty {
                entry.name
            } else {
                "\(entry.name)\n\(entry.content)"
            }
        }.joined(separator: "\n\n")
    }

    // MARK: - Private Helpers

    private func normalizeLineEndings(_ text: String) -> String {
        text
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")
    }
}
