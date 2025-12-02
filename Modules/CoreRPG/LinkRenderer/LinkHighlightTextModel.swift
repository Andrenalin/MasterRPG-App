// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor @Observable
public final class LinkHighlightTextModel {    
    public init(linkControllable: LinkControllable?, text: String, highlightedText: String? = nil, toggler: ((UUID, NetworkModules) async -> Void)? = nil, shareResult: ShareValueResult? = nil, editAction: ((ItemRowModel) -> Bool)? = nil) {
        self.linkControllable = linkControllable
        self.text = text
        self.highlightedText = highlightedText
        self.linkLocations = LinkHighLightLocations()
        self.toggler = toggler
        self.shareResult = shareResult
        self.editAction = editAction
    }

    @ObservationIgnored
    let linkControllable: (any LinkControllable)?
    @ObservationIgnored
    let toggler: ((UUID, NetworkModules) async -> Void)?
    @ObservationIgnored
    let shareResult: ShareValueResult?
    @ObservationIgnored
    let editAction: ((ItemRowModel) -> Bool)?
    
    @ObservationIgnored private(set) public var text: String
    @ObservationIgnored private var highlightedText: String?
    
    var linkLocations: LinkHighLightLocations

    var updated: UUID = UUID()
    @ObservationIgnored var lastUpdated: UUID = UUID()
    
    public func reset(highlightedText: String) {
        guard self.highlightedText != highlightedText else { return }
        self.highlightedText = highlightedText
        updated = UUID()
    }

    public func reset(text: String) {
        guard self.text != text else { return }
        self.text = text
        updated = UUID()
    }

    func handle(link: LinkReplaceModel) {
        guard let linkControllable else { return }
        let searchUrl = link.markDown.split(separator: "]").last!.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        guard let url = URL(string: searchUrl) else { return }

        var repariedText = text
        _ = LinkReplaceController.linksRepair(for: &repariedText)
        
        let updatedText = linkControllable.handleTextLink(url: url, in: repariedText, shareResult: shareResult, toggler: toggler, editAction: editAction)

        reset(text: updatedText)
    }
}

extension LinkHighlightTextModel {
    var displayText: [HighlightedTextComponent] {
        var boldRange: Range<String.Index>? = nil
        var repairedText = text
        let links = LinkReplaceController.linksRepair(for: &repairedText)
        return components(for: repairedText, range: repairedText.startIndex..<repairedText.endIndex, links: links, boldRange: &boldRange)
    }
    
    func components(for text: String, range: Range<String.Index>, links: [LinkReplaceModel], boldRange: inout Range<String.Index>?, isBold: Bool = false, deep: Int = 0) -> [HighlightedTextComponent] {
        var index = range.lowerBound
        var lastIndex = index
        var result: [HighlightedTextComponent] = []
        while index != range.upperBound && index < text.endIndex {
            // Link Begin Test
            if text[index] == Character(LinkExpandHighLightValues.begin.rawValue) {
                //print("Link Begin:\(text[index])")
                if lastIndex != index && index > lastIndex {
                    let previousRange = lastIndex..<index
                    result.append(contentsOf: hightlight(text: text, range: previousRange, isBold: boldRange != nil, deep: deep))
                }
                var nextIndex = text.index(after: index)
                if boldRange != nil {
                    boldRange = nextIndex..<range.upperBound
                }

                let beginRanges = text.ranges(of: LinkExpandHighLightValues.begin.rawValue).filter { $0.lowerBound >= nextIndex }
                var endRanges = text.ranges(of: LinkExpandHighLightValues.end.rawValue).filter { $0.lowerBound >= nextIndex }

                var endRange = endRanges.first
                endRanges.removeFirst()
                for beginRange in beginRanges {
                    if let endRange  {
                        if beginRange.lowerBound > endRange.upperBound {
                            break
                        }
                    } else {
                        break
                    }
                    endRange = endRanges.first
                    endRanges.removeFirst()
                }
                if let endRange {
                    result.append(HighlightedTextComponent(text: Text("\(Image(systemName: "arrowshape.right.fill"))")
                            .customAttribute(LinkIconExpandedAttribute(isStart: true)), string: LinkExpandHighLightValues.begin.rawValue, range: index..<nextIndex))
                    result.append(contentsOf: components(for: text, range: nextIndex..<endRange.lowerBound, links: links, boldRange: &boldRange, deep: deep + 1))
                    //print("Link End:\(text[nextIndex..<endRange.lowerBound])")
                    nextIndex = endRange.upperBound
                    index = endRange.lowerBound
                    if boldRange != nil {
                        boldRange = nextIndex..<range.upperBound
                    }
                }
                lastIndex = nextIndex
            }
            
            // check for bold
            if text[index] == Character(LinkExpandHighLightValues.bold.rawValue) {
                //print("Check bold:\(text[index])")
                let nextIndex = text.index(after: index)
                if nextIndex != range.upperBound && text[nextIndex] == Character(LinkExpandHighLightValues.bold.rawValue) {
                    //print("found bold:\(text[index])")
                    // found bold
                    if var range = boldRange {
                        // bold end
                        range = range.lowerBound..<index
                        //print("Found bold:\(text[range])")
                        result.append(contentsOf: hightlight(text: text, range: range, isBold: true, deep: deep))
                        boldRange = nil
                        lastIndex = text.index(after: nextIndex)
                    } else {
                        // bold start
                        //print("Bold Start detected ")
                        let rangeStart = text.index(after: nextIndex)
                        if rangeStart != range.upperBound {
                            boldRange = rangeStart..<range.upperBound
                        }
                        if lastIndex != index && index > lastIndex {
                            let range = lastIndex..<index
                            result.append(contentsOf: hightlight(text: text, range: range, isBold: false, deep: deep))
                        }
                        lastIndex = rangeStart
                    }
                    index = nextIndex
                }
            }
            
            if let link = links.first(where: { $0.range.lowerBound == index }) {
                if lastIndex != index && index > lastIndex {
                    let previousRange = lastIndex..<index
                    result.append(contentsOf: hightlight(text: text, range: previousRange, isBold: boldRange != nil, deep: deep))
                }
                result.append(HighlightedTextComponent(text: Text("\(Image(systemName: link.icon))")
                    .customAttribute(LinkIconAttribute(linkModel: link))
                    .bold(boldRange != nil), string: link.icon, range: link.range))
                
                result.append(contentsOf: hightlight(text: "\(link.name)", range: link.name.startIndex..<link.name.endIndex, isBold: boldRange != nil, deep: deep, custom: [LinkHighlightAttribute(linkModel: link)]))
                result.append(HighlightedTextComponent(text: Text("  ")
                    .customAttribute(LinkIconExpandedAttribute(isStart: false)), string: LinkExpandHighLightValues.space.rawValue, range: link.name.startIndex..<link.name.endIndex))

                lastIndex = link.range.upperBound
                index = text.index(before: link.range.upperBound)
                if boldRange != nil {
                    boldRange = lastIndex..<range.upperBound
                }
            }
            
            index = text.index(after: index)
        }
        if lastIndex < range.upperBound {
            let previousRange = lastIndex..<range.upperBound
            result.append(contentsOf: hightlight(text: text, range: previousRange, isBold: false, deep: deep))
        }
        return result
    }
    
    private func hightlight(text: String, range: Range<String.Index>, isBold: Bool, deep: Int, custom: [any TextAttribute] = []) -> [HighlightedTextComponent] {
        if let searchText = highlightedText {
            let restText = String(text[range])
            let searchRanges = restText.ranges(of: searchText, options: .caseInsensitive)
            var searchHighlightRanges = searchRanges.map {
                return highlightComponent(text: String(restText[$0]), range: $0, isBold: isBold, deep: deep, attributes: custom + [SearchHighlightAttribute()])
            }
            var restResult: [HighlightedTextComponent] = []
            for restRange in restText.remainingRanges(from: searchHighlightRanges.map(\.range)) {
                restResult.append(highlightComponent(text: String(restText[restRange]), range: restRange, isBold: isBold, deep: deep, attributes: custom))
            }
            searchHighlightRanges.append(contentsOf: restResult)
            return searchHighlightRanges.sorted(by: { $0.range.lowerBound < $1.range.lowerBound })
        } else {
            return [highlightComponent(text: String(text[range]), range: range, isBold: isBold, deep: deep, attributes: custom)]
        }
    }
    
    private func highlightComponent(text: String, range: Range<String.Index>, isBold: Bool, deep: Int, attributes: [any TextAttribute]) -> HighlightedTextComponent {
        var textUI = attributes.reduce(Text(text).bold(isBold)) { $0.customAttribute($1) }
        if deep > 0 {
            textUI = textUI.customAttribute(LinkExpandedAttribute(deep: deep)).customAttribute(OnboardingEmphasisAttribute())
        }
        return HighlightedTextComponent(text: textUI, string: text, range: range)
    }
}
