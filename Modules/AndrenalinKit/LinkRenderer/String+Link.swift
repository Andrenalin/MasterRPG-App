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
    
    private func findEndRange(afterRange: Range<String.Index>) -> Range<String.Index>? {
        guard afterRange.lowerBound != endIndex && self[afterRange.lowerBound] == Character(LinkExpandHighLightValues.begin.rawValue) else { return nil }
        let beginRanges = ranges(of: LinkExpandHighLightValues.begin.rawValue).filter { $0.lowerBound >= afterRange.lowerBound }
        guard let startRange = beginRanges.first else { return nil }

        var endRange = range(of: String(LinkExpandHighLightValues.end.rawValue), range: startRange.upperBound..<afterRange.upperBound)
        for beginRange in beginRanges.dropFirst() {
            if let testEndRange = endRange {
                if beginRange.lowerBound < testEndRange.upperBound {
                    endRange = range(of: String(LinkExpandHighLightValues.end.rawValue), range: testEndRange.upperBound..<endIndex)
                } else {
                    // found
                    break
                }
            } else {
                return nil
            }
        }
        if let endRange {
            return startRange.lowerBound..<endRange.upperBound
        }
        return endRange
    }
}
