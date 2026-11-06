// @copyright André Trettin

import Foundation
import SwiftUI

extension String {
    public func toggleLink(url: String, with insertedText: String, replace: Bool = false, remove: Bool = false) -> String {
        guard let urlRange = self.range(of: url) else { return self }
        var updatedText = self
        let inserted = LinkExpandHighLightValues.begin.rawValue + insertedText + LinkExpandHighLightValues.end.rawValue
        
        let endRange = findEndRange(afterRange: urlRange.upperBound..<endIndex)
        guard let endRange else {
            let insertIndex = urlRange.upperBound
            if insertIndex == endIndex {
                // append
                updatedText.append(inserted)
            } else {
                updatedText.insert(contentsOf: inserted, at: insertIndex)
            }
            return updatedText
        }
        updatedText.replaceSubrange(endRange, with: replace ? inserted : "")
        if remove {
            updatedText.replaceSubrange(urlRange, with: insertedText)
        }
        return updatedText
    }
    
    /// The range from the begin marker at `afterRange.lowerBound` to the end marker that closes
    /// it, `nil` when the text there does not start with a begin marker. Pairs the markers like
    /// the renderer (`matchingLinkEnd(after:)`); a text whose markers do not balance, such as an
    /// expansion that holds a lone begin marker, closes at the first end marker instead, so
    /// the link can still be collapsed.
    private func findEndRange(afterRange: Range<String.Index>) -> Range<String.Index>? {
        guard afterRange.lowerBound != endIndex && self[afterRange.lowerBound] == Character(LinkExpandHighLightValues.begin.rawValue) else { return nil }
        let beginUpper = index(after: afterRange.lowerBound)
        if let end = matchingLinkEnd(after: beginUpper) {
            return afterRange.lowerBound..<end.upperBound
        }
        guard let firstEnd = range(of: String(LinkExpandHighLightValues.end.rawValue), range: beginUpper..<endIndex) else { return nil }
        return afterRange.lowerBound..<firstEnd.upperBound
    }

    /// The end marker that closes the begin marker just before `start`, honouring nested
    /// begin/end pairs. `nil` when the markers after `start` do not balance.
    func matchingLinkEnd(after start: String.Index) -> Range<String.Index>? {
        let begins = ranges(of: LinkExpandHighLightValues.begin.rawValue).filter { $0.lowerBound >= start }
        let ends = ranges(of: LinkExpandHighLightValues.end.rawValue).filter { $0.lowerBound >= start }
        var events: [(range: Range<String.Index>, isBegin: Bool)] = begins.map { ($0, true) }
        events.append(contentsOf: ends.map { ($0, false) })
        events.sort { $0.range.lowerBound < $1.range.lowerBound }

        var depth = 1
        for event in events {
            depth += event.isBegin ? 1 : -1
            if depth == 0 { return event.range }
        }
        return nil
    }
}
