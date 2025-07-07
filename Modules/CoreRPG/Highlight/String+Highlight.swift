// @copyright André Trettin

import Foundation

extension String {
    /// Find all ranges of the given substring
    ///
    /// - Parameters:
    ///   - substring: The substring to find ranges for
    ///   - options: Compare options
    ///   - locale: Locale used for finding
    /// - Returns: Array of all ranges of the substring
    func ranges(of substring: String, options: CompareOptions = [], locale: Locale? = nil, in subRange: Range<Index>? = nil) -> [Range<Index>] {
        var ranges: [Range<Index>] = []
        let searchEndIndex = (subRange == nil) ? self.endIndex : subRange!.upperBound
        while let range = range(of: substring, options: options, range: (ranges.last?.upperBound ?? subRange?.lowerBound ?? self.startIndex)..<searchEndIndex, locale: locale) {
            ranges.append(range)
        }
        return ranges
    }


    /// Find all remaining ranges given `ranges`
    ///
    /// - Parameters:
    ///   - ranges: A set of ranges
    /// - Returns: All the ranges that are not part of `ranges`
    func remainingRanges(from ranges: [Range<Index>]) -> [Range<Index>] {
        var result = [Range<Index>]()

        // Sort the input ranges to process them in order
        let sortedRanges = ranges.sorted { $0.lowerBound < $1.lowerBound }

        // Start from the beginning of the string
        var currentIndex = self.startIndex

        for range in sortedRanges {
            if currentIndex < range.lowerBound {
                // Add the range from currentIndex to the start of the current range
                result.append(currentIndex..<range.lowerBound)
            }

            // Move currentIndex to the end of the current range
            currentIndex = range.upperBound
        }

        // If there's remaining text after the last range, add it as well
        if currentIndex < self.endIndex {
            result.append(currentIndex..<self.endIndex)
        }

        return result
    }
}
