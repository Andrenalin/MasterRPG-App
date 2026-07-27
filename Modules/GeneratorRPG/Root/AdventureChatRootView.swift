// @copyright André Trettin

import CoreRPG
import FoundationModels
import SwiftUI

enum AdventureChatBlockOrigin: Hashable {
    case sheet
    case generated
}

struct AdventureChatBlockSnapshot: Identifiable, Hashable {
    let id: String
    let index: Int
    let title: String
    let content: String
    let isPending: Bool
    let origin: AdventureChatBlockOrigin
    var source: ItemRowModel? = nil
    var parentSource: ItemRowModel? = nil
    var batchID: String? = nil

    var isEmpty: Bool {
        title.isEmpty && content.isEmpty
    }

    var isSelectable: Bool {
        origin == .generated
    }

    func titleForSheet(index: Int) -> String {
        if title.isEmpty {
            return String(localized: "Adventure Block \(index + 1)", bundle: .module)
        }
        return title
    }

    static func blocks(
        from entries: [BlockEntryGenModel.PartiallyGenerated],
        batchID: String? = nil,
        parentSource: ItemRowModel? = nil
    ) -> [AdventureChatBlockSnapshot] {
        entries.enumerated().map { offset, entry in
            let title = cleaned(entry.title)
            let content = cleaned(entry.content)
            let idPrefix = batchID ?? "preview"
            return AdventureChatBlockSnapshot(
                id: "\(idPrefix)-\(offset)-\(entry.stableID)",
                index: offset,
                title: title,
                content: content,
                isPending: title.isEmpty || content.isEmpty,
                origin: .generated,
                source: nil,
                parentSource: parentSource,
                batchID: batchID
            )
        }
    }

    private static func cleaned(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct AdventureChatSeedBlock: Identifiable, Hashable {
    let id: String
    let title: String
    let content: String
    let depth: Int
    let source: ItemRowModel
}

enum AdventureSheetContextBuilder {
    @MainActor
    static func seedBlocks(from sheetModel: SheetModel) -> [AdventureChatSeedBlock] {
        var blocks: [AdventureChatSeedBlock] = []
        collect(from: sheetModel, path: "root", depth: 0, into: &blocks)
        return blocks
    }

    @MainActor
    static func sourceBlocks(from sheetModel: SheetModel) -> [AdventureChatBlockSnapshot] {
        var blocks: [AdventureChatSeedBlock] = []
        collectEntries(from: sheetModel.entries, path: "entry", depth: 1, into: &blocks)

        if blocks.isEmpty {
            let title = cleaned(sheetModel.name)
            let content = cleaned(sheetModel.description)
            if !title.isEmpty || !content.isEmpty {
                blocks.append(
                    AdventureChatSeedBlock(
                        id: "root",
                        title: title.isEmpty
                            ? String(localized: "Adventure", bundle: .module)
                            : title,
                        content: content,
                        depth: 0,
                        source: sheetModel.source
                    )
                )
            }
        }

        return blocks.enumerated().map { offset, block in
            AdventureChatBlockSnapshot(
                id: "sheet-\(block.id)",
                index: offset,
                title: block.title,
                content: block.content,
                isPending: false,
                origin: .sheet,
                source: block.source
            )
        }
    }

    @MainActor
    static func initialPrompt(for sheetModel: SheetModel) -> String? {
        let blocks = seedBlocks(from: sheetModel)
        guard !blocks.isEmpty else { return nil }

        let context = blocks
            .prefix(16)
            .map { block in
                let indent = String(repeating: "  ", count: min(block.depth, 3))
                return "\(indent)- \(block.title): \(truncated(block.content, limit: 320))"
            }
            .joined(separator: "\n")

        return """
        Summarize these existing adventure sheet notes into a compact starting context for our chat. Preserve named places, NPCs, conflicts, secrets, and open story hooks. After the summary, propose the next useful adventure blocks to create.

        Existing sheet:
        \(context)
        """
    }

    @MainActor
    static func blockGenerationPrompt(for sheetModel: SheetModel) -> String? {
        let blocks = sourceBlocks(from: sheetModel)
        guard !blocks.isEmpty else { return nil }

        let sheetText = blocks
            .prefix(20)
            .map { block in
                """
                Title: \(block.titleForSheet(index: block.index))
                Content: \(truncated(block.content, limit: 420))
                """
            }
            .joined(separator: "\n\n")

        return """
        Generate adventure sheet blocks from the following SheetModel text. Preserve the existing meaning, but rewrite each result as a clear playable block with a concise title and useful content. Prefer scenes, story beats, secrets, NPC motives, complications, choices, and outcomes. Return structured blocks suitable for saving back into an adventure sheet.

        SheetModel text:
        \(sheetText)
        """
    }

    @MainActor
    private static func collect(
        from sheetModel: SheetModel,
        path: String,
        depth: Int,
        into blocks: inout [AdventureChatSeedBlock]
    ) {
        let title = cleaned(sheetModel.name)
        let content = cleaned(sheetModel.description)

        if !title.isEmpty || !content.isEmpty {
            blocks.append(
                AdventureChatSeedBlock(
                    id: path,
                    title: title.isEmpty
                        ? String(localized: "Untitled", bundle: .module)
                        : title,
                    content: content,
                    depth: depth,
                    source: sheetModel.source
                )
            )
        }

        for entry in sheetModel.entries.enumerated() {
            collect(from: entry.element, path: "\(path).entry.\(entry.offset)", depth: depth + 1, into: &blocks)
        }

        for entry in sheetModel.inlineEntries.enumerated() {
            collect(from: entry.element, path: "\(path).inline.\(entry.offset)", depth: depth + 1, into: &blocks)
        }
    }

    @MainActor
    private static func collectEntries(
        from entries: [SheetModel],
        path: String,
        depth: Int,
        into blocks: inout [AdventureChatSeedBlock]
    ) {
        for entry in entries.enumerated() {
            let sheet = entry.element
            let title = cleaned(sheet.name)
            let content = cleaned(sheet.description)
            let entryPath = "\(path).\(entry.offset)"

            if !title.isEmpty || !content.isEmpty {
                blocks.append(
                    AdventureChatSeedBlock(
                        id: entryPath,
                        title: title.isEmpty
                            ? String(
                                localized: "Adventure Block \(blocks.count + 1)",
                                bundle: .module
                            )
                            : title,
                        content: content,
                        depth: depth,
                        source: sheet.source
                    )
                )
            }

            collectEntries(from: sheet.entries, path: "\(entryPath).entry", depth: depth + 1, into: &blocks)
        }
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncated(_ value: String, limit: Int) -> String {
        let value = cleaned(value)
        guard value.count > limit else { return value }
        return "\(value.prefix(limit))..."
    }
}

enum AdventureChatPreviewData {
    nonisolated static let rootItemID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x90, 0x01))
    nonisolated static let rubyItemID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x90, 0x02))
    nonisolated static let verdantItemID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x90, 0x03))
    nonisolated static let indigoItemID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x90, 0x04))
    nonisolated static let rubyEntryID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x90, 0x12))
    nonisolated static let verdantEntryID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x90, 0x13))
    nonisolated static let indigoEntryID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x90, 0x14))

    @MainActor static var sheetModel: SheetModel {
        let firstEntrySource = ItemRowModel(itemId: rubyItemID, entryId: rubyEntryID, typeId: .adventure)
        let secondEntrySource = ItemRowModel(itemId: verdantItemID, entryId: verdantEntryID, typeId: .adventure)
        let thirdEntrySource = ItemRowModel(itemId: indigoItemID, entryId: indigoEntryID, typeId: .adventure)
        let rootSource = ItemRowModel(itemId: rootItemID, typeId: .adventure)
        return SheetModel(
            source: rootSource,
            level: 0,
            name: "The Seven Rooms",
            description: "A lost fortress built by dwarves for elven envoys, with each colored hall hiding a political vow.",
            entries: [
                SheetModel(
                    source: firstEntrySource,
                    level: 1,
                    name: "Ruby Gate",
                    description: "The red chamber tests courage through a silent duel against a remembered failure.",
                    entries: []
                ),
                SheetModel(
                    source: secondEntrySource,
                    level: 1,
                    name: "Verdant Archive",
                    description: "The green room preserves the original peace treaty in living roots that answer only honest questions.",
                    entries: []
                ),
                SheetModel(
                    source: thirdEntrySource,
                    level: 1,
                    name: "Indigo Betrayal",
                    description: "The blue-violet hall replays the night an elven diplomat broke the fortress wards to save one child.",
                    entries: []
                )
            ]
        )
    }

    static var blocks: [AdventureChatBlockSnapshot] {
        [
            AdventureChatBlockSnapshot(
                id: "preview-ruby",
                index: 0,
                title: "The Ruby Gate",
                content: "The first room asks each hero to cross a bridge of red glass while whispers name the choice they regret most.",
                isPending: false,
                origin: .generated
            ),
            AdventureChatBlockSnapshot(
                id: "preview-verdant",
                index: 1,
                title: "The Verdant Archive",
                content: "Living vines bind treaty tablets to the walls. Cutting them reveals routes, but preserving them earns an elven spirit guide.",
                isPending: false,
                origin: .generated
            ),
            AdventureChatBlockSnapshot(
                id: "preview-indigo",
                index: 2,
                title: "The Indigo Betrayal",
                content: "A moonlit chamber repeats the night the fortress changed hands, allowing players to question echoes of both sides.",
                isPending: false,
                origin: .generated
            ),
            AdventureChatBlockSnapshot(
                id: "preview-forge",
                index: 3,
                title: "The White Forge",
                content: "The final hall can reforge one broken promise into a magical key, but only if the party agrees what must stay lost.",
                isPending: false,
                origin: .generated
            )
        ]
    }
}
