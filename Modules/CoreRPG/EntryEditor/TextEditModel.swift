// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor @Observable public final class TextEditModel {
    public init(linkRegisterController: LinkRegisterController?) {
        self.linkRegisterController = linkRegisterController
    }
    
    let linkRegisterController: LinkRegisterController?
    var source: ItemRowModel = ItemRowModel(itemId: UUID(), typeId: .none)
    
    public var name: String = ""
    public var text: String = ""
    
    public var attributedName: AttributedString = AttributedString("")
    public var attributedText: AttributedString = AttributedString("")
    
    var nameLinks: [LinkRegisterModel] = []
    var links: [LinkRegisterModel] = []
    private var nameUpdateTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    
    // Performance: Cache the last processed text to avoid redundant AttributedString creation
    private var lastProcessedName: String = ""
    private var lastProcessedText: String = ""
    
    public func reset(text: String, source: ItemRowModel) {
        // Cancel any pending updates
        updateTask?.cancel()
        
        self.source = source
        self.text = text
        lastProcessedText = ""
        
        resetAttributedText()
    }
    
    func reset(entry: any EntryDataAccessible, source: ItemRowModel) {
        // Cancel any pending updates
        nameUpdateTask?.cancel()
        updateTask?.cancel()
        
        self.source = source
        name = entry.name
        text = entry.content
        lastProcessedName = ""
        lastProcessedText = ""
        
        resetAttributedName()
        resetAttributedText()
    }

    public func resetAttributedName() {
        guard name != lastProcessedName else { return }
        lastProcessedName = name

        let result = attributedText(from: name)
        nameLinks = result.links
        attributedName = result.text
    }
    
    public func resetAttributedText() {
        // Performance: Skip processing if text hasn't changed
        guard text != lastProcessedText else { return }
        lastProcessedText = text

        let result = attributedText(from: text)
        links = result.links
        attributedText = result.text
    }

    public func resetNameText() {
        name <=> plainText(from: attributedName, links: nameLinks)
        lastProcessedName = ""
    }
    
    public func resetText() {
        text <=> plainText(from: attributedText, links: links)
        lastProcessedText = ""
    }

    public func updateNameLinks() {
        nameUpdateTask?.cancel()

        nameUpdateTask = delayedTask(.settleDelay) { [self] in
            guard linkRegisterController != nil else {
                name = String(attributedName.characters)
                return
            }

            resetNameText()
            resetAttributedName()
        }
    }

    public func updateLinks() {
        // Cancel previous update task to avoid redundant work
        updateTask?.cancel()

        // Debounce updates to avoid excessive AttributedString recalculation
        updateTask = delayedTask(.settleDelay) { [self] in
            guard linkRegisterController != nil else { return }

            resetText()
            resetAttributedText()
        }
    }

    private func attributedText(from value: String) -> (text: AttributedString, links: [LinkRegisterModel]) {
        guard let linkRegisterController else {
            return (AttributedString(value), [])
        }

        // Identical links (typically written with the same number, as in the quick editor) are
        // numbered by position first, so each one is found at its own place below.
        var numberedValue = value
        _ = LinkReplaceController.linksRepair(for: &numberedValue)

        var attributedValue = AttributedString(numberedValue)
        let parsedLinks = linkRegisterController.linkRegisterModel(in: numberedValue, for: source)

        var occurrences = MarkDownOccurrences(text: numberedValue)
        let sortedLinks = parsedLinks.compactMap {
            link -> (range: Range<AttributedString.Index>, link: LinkRegisterModel)? in
            guard let markDown = link.markDown,
                  let stringRange = occurrences.next(markDown),
                  let range = Range(stringRange, in: attributedValue) else {
                return nil
            }
            return (range, link)
        }
        .sorted { $0.range.lowerBound > $1.range.lowerBound }

        for item in sortedLinks {
            var linkedText = AttributedString(item.link.name)
            linkedText[keyPath: \.linkContent] = item.link.id
            attributedValue.replaceSubrange(item.range, with: linkedText)
        }

        return (attributedValue, parsedLinks)
    }

    private func plainText(
        from attributedValue: AttributedString,
        links: [LinkRegisterModel]
    ) -> String {
        var result = ""

        for run in attributedValue.runs {
            let substring = String(attributedValue[run.range].characters)
            guard let linkId = run.linkContent else {
                result.append(substring)
                continue
            }
            let link = links.first { $0.id == linkId }
                ?? linkRegisterController?.linkRegisterModel(linkId: linkId)
            guard let link else {
                result.append(substring)
                continue
            }
            result.append(link.markDown ?? link.urlMarkDown)
        }

        return result
    }
}
