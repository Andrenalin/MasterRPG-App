// @copyright André Trettin

import FoundationModels

extension Array where Element == Transcript.Segment {
    func textContentJoined() -> String? {
        let text = compactMap { segment -> String? in
            switch segment {
            case .text(let textSegment):
                return textSegment.content
            case .structure(let structuredSegment):
                return structuredSegment.description
#if compiler(>=6.4)
            case .attachment(let attachmentSegment):
                return attachmentSegment.label
#endif
            @unknown default:
                return String(describing: segment)
            }
        }.joined(separator: " ")

        return text.isEmpty ? nil : text
    }
}
