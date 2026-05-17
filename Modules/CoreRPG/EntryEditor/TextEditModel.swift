// @copyright André Trettin

import Foundation
import SwiftData
import SwiftUI

@MainActor @Observable public final class TextEditModel {
    public init(linkRegisterController: LinkRegisterController?) {
        self.linkRegisterController = linkRegisterController
    }
    
    let linkRegisterController: LinkRegisterController?
    var source: ItemRowModel = ItemRowModel(itemId: UUID(), typeId: .none)
    
    public var name: String = ""
    public var text: String = ""
    
    public var attributedText: AttributedString = AttributedString("")
    
    var links: [LinkRegisterModel] = []
    private var updateTask: Task<Void, Never>?
    
    // Performance: Cache the last processed text to avoid redundant AttributedString creation
    private var lastProcessedText: String = ""
    
    public func reset(text: String, source: ItemRowModel) {
        // Cancel any pending updates
        updateTask?.cancel()
        
        self.source = source
        self.text = text
        
        resetAttributedText()
    }
    
    func reset(entry: any EntryDataAccessable, source: ItemRowModel) {
        // Cancel any pending updates
        updateTask?.cancel()
        
        self.source = source
        name = entry.name
        text = entry.content
        
        resetAttributedText()
    }
    
    public func resetAttributedText() {
        // Performance: Skip processing if text hasn't changed
        guard text != lastProcessedText else { return }
        lastProcessedText = text
        
        var att = AttributedString(text)
        guard let links = linkRegisterController?.linkRegisterModel(in: text, for: source) else { 
            self.links = []
            self.attributedText = att
            return 
        }
        
        self.links = links
        
        // Performance optimization: Process links in reverse order to avoid index invalidation
        // This prevents the need to recalculate ranges after each replacement
        let sortedLinks = links.compactMap { link -> (range: Range<AttributedString.Index>, link: LinkRegisterModel)? in
            guard let markDown = link.markDown, let range = att.range(of: markDown) else { return nil }
            return (range, link)
        }.sorted { $0.range.lowerBound > $1.range.lowerBound }
        
        for item in sortedLinks {
            var linkAtt = AttributedString(item.link.name)
            linkAtt[keyPath: \.linkContent] = item.link.id
            att.replaceSubrange(item.range, with: linkAtt)
        }
        
        self.attributedText = att
    }
    
    public func resetText() {
        // Build plain text from attributedText by converting link attributed runs back to Markdown
        // We expect the custom attribute key path `\.linkContent` to contain the UUID of the link (LinkDataModel.id)
        var result = ""
        let att = attributedText
        
        // Iterate over runs, preserving non-link text and converting link runs
        for run in att.runs {
            let range = run.range
            let substring = String(att[range].characters)
            
            if let linkId = run.linkContent {
                if let link = linkRegisterController?.linkRegisterModel(linkId: linkId) {
                    let markdown = link.markDown ?? link.urlMarkDown
                    result.append(markdown)
                } else {
                    result.append(substring)
                }
            } else {
                result.append(substring)
            }
        }
        
        // Update model state
        text <=> result
        // Reset cache when text is explicitly updated
        lastProcessedText = ""
    }
    
    public func updateLinks() {
        // Cancel previous update task to avoid redundant work
        updateTask?.cancel()
        
        // Debounce updates to avoid excessive AttributedString recalculation
        updateTask = Task { @MainActor in
            // Small delay to batch rapid changes
            try? await Task.sleep(for: .milliseconds(100))
            
            guard !Task.isCancelled else { return }
            guard linkRegisterController != nil else { return }
            
            resetText()
            resetAttributedText()
        }
    }
}
