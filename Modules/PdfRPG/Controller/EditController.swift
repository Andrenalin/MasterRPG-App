// @copyright André Trettin

import CoreGraphics
import CoreRPG
import CoreTransferable
import Foundation
#if !os(tvOS)
import GeneratorRPG
#endif

struct LinkPdfModuleTransferable: LinkDataTransferable {
    let module: NetworkModules
    let itemId: UUID
    let entryId: UUID?
    let name: String
    let isMove: Bool

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.linkRepresentation)
    }
}

/// See CODE_AUDIT_EditItem §9.1 — genericized in `GenericEditController` (CoreRPG);
/// this module has no extra stored state beyond the generic default (its extra
/// bookmark/extraction behavior below needs no stored properties of its own).
typealias EditController = GenericEditController<PdfModel>

extension EditController: @retroactive EntryDataEditable {
    public var linkModules: [NetworkModules] { [] }
    
    public func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        SelectionRoute.selection
    }

    public func create(name: String, content: String) -> PdfEntryModel {
        PdfEntryModel(id: UUID(), name: name, content: content, pageNumber: "", bounds: .zero)
    }

    @MainActor public func merge(itemId: UUID, entries: [PdfEntryModel]) -> [PdfEntryModel] {
        entries
    }

    public func merge(itemId: UUID, entries: [PdfEntryModel], recoverEntries: [CoreRPG.ItemRowModel]?, forceSave: Bool) -> [ItemRowModel] {
        []
    }
    
    public func quickEditorDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        SelectionRoute.selection
    }
}

extension EditController {
    /// - Parameter forceSave: `true` from the viewer's selection bar: a bookmark is library
    ///   content, kept also when it is added during a game.
    @MainActor func addBookmark(itemId: UUID, entry: PdfEntryModel, forceSave: Bool) {
        guard let item = editModel(for: itemId) else { return }
        item.entries.append(entry)
        save(
            updated: item,
            message: String(localized: "Added Bookmark", bundle: .module),
            forceSave: forceSave
        )
    }
    
    func createBookmark(content: String, page: String, bounds: CGRect) -> PdfEntryModel {
        let name: String
        // Split on any whitespace: a newline or tab stayed in the name. See CODE_AUDIT_29 §5.24.
        if let nameWord = content.split(whereSeparator: \.isWhitespace).first {
            name = String(nameWord)
        } else {
            name = String(localized: "Unnamed", bundle: .module)
        }
        return PdfEntryModel(id: UUID(), name: name, content: content, pageNumber: page, bounds: bounds, displayState: DisplayStateMask.fullVisible.rawValue)
    }
}

// MARK: - Apply extracted PDF content to a PdfModel using the EditController

#if !os(tvOS)
extension EditController {
    /// - Parameter pageLabel: the label of the document's page at a 1-based position (what the
    ///   bookmark list shows and the viewer looks a bookmark up by), or `nil` when it is unknown.
    ///   The summary names pages by position. See CODE_AUDIT_22 §5.8.
    @MainActor func applyExtractedContent(
        _ content: PdfSummaryAnalysis,
        to itemId: UUID,
        selection: PdfPropertySelection,
        forceSave: Bool,
        pageLabel: (Int) -> String? = { _ in nil }
    ) {
        // One save for the selected title, description and tags, and one undo step with the
        // sections; it saved up to four times. See CODE_AUDIT_Edit_Save §7.1.
        asOneUndoStep(String(localized: "Applied PDF sections as bookmarks", bundle: .module)) {
            if selection.applyTitle || selection.applyDescription || selection.applyTags {
                reset(
                    name: selection.applyTitle ? content.title : nil,
                    description: selection.applyDescription ? content.summary : nil,
                    tags: selection.applyTags ? content.tags : nil,
                    itemId: itemId,
                    forceSave: forceSave
                )
            }
            if selection.applySections && !content.sections.isEmpty {
                appendSectionsAsEntries(content.sections, to: itemId, forceSave: forceSave, pageLabel: pageLabel)
            }
        }
    }

    @MainActor private func appendSectionsAsEntries(_ sections: [PdfSection], to itemId: UUID, forceSave: Bool, pageLabel: (Int) -> String?) {
        guard let item = editModel(for: itemId) else { return }

        let newEntries = sections.map { PdfBookmarkMerge.entry(for: $0, pageLabel: pageLabel) }
        item.entries.append(contentsOf: newEntries)
        
        save(
            updated: item,
            message: String(localized: "Applied PDF sections as bookmarks", bundle: .module),
            forceSave: forceSave
        )
    }

    /// Adds the generated sections as bookmarks for the batch "Extract Information", skipping
    /// sections that already have a bookmark with the same name and page (`PdfBookmarkMerge`).
    /// - Returns: the number of bookmarks added.
    /// Forced: batch extraction is an explicit library save, also during a game, like the
    /// description and tags it writes with. See CODE_AUDIT_Edit_Save §5.19.
    @MainActor func addExtractedBookmarks(_ sections: [PdfSection], to itemId: UUID, pageLabel: (Int) -> String?) -> Int {
        guard let item = editModel(for: itemId) else { return 0 }
        let newEntries = PdfBookmarkMerge.newEntries(for: sections, existing: item.entries, pageLabel: pageLabel)
        guard !newEntries.isEmpty else { return 0 }
        item.entries.append(contentsOf: newEntries)
        save(
            updated: item,
            message: String(localized: "Applied PDF sections as bookmarks", bundle: .module),
            forceSave: true
        )
        return newEntries.count
    }
}

/// Turns generated PDF sections into bookmarks. Pure, so it is tested.
enum PdfBookmarkMerge {
    /// Bounds, because the sections are generated from the PDF's text, which can come from an
    /// import or a shared campaign (same limits as `BatchSummaryMerge`).
    static let maximumNameLength = 100
    static let maximumContentLength = 500

    /// The bookmark for one section. The summary names pages by 1-based position, the bookmark
    /// stores the page label (see CODE_AUDIT_22 §5.8).
    static func entry(for section: PdfSection, pageLabel: (Int) -> String?) -> PdfEntryModel {
        PdfEntryModel(
            id: UUID(),
            name: section.heading,
            content: section.summary,
            pageNumber: section.pageNumber.map { pageLabel($0) ?? String($0) } ?? "",
            bounds: .zero,
            displayState: DisplayStateMask.fullVisible.rawValue
        )
    }

    /// The bookmarks to add for the batch: bounded, without an empty name, and without a section
    /// whose name and page match an existing bookmark or an earlier section, so running the
    /// batch again adds nothing twice. Existing bookmarks are never changed.
    static func newEntries(for sections: [PdfSection], existing: [PdfEntryModel], pageLabel: (Int) -> String?) -> [PdfEntryModel] {
        var seen = Set(existing.map { key(name: $0.name, page: $0.pageLabel) })
        var result: [PdfEntryModel] = []
        for section in sections {
            let heading = String(section.heading.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumNameLength))
            guard !heading.isEmpty else { continue }
            let summary = String(section.summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumContentLength))
            let entry = entry(
                for: PdfSection(heading: heading, summary: summary, pageNumber: section.pageNumber),
                pageLabel: pageLabel
            )
            guard seen.insert(key(name: entry.name, page: entry.pageLabel)).inserted else { continue }
            result.append(entry)
        }
        return result
    }

    private struct Key: Hashable {
        let name: String
        let page: String
    }

    private static func key(name: String, page: String) -> Key {
        Key(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            page: page.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
#endif
