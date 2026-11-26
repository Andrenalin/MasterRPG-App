// @copyright André Trettin

import Foundation
import Observation
import os.log

// Split out of ItemControllable.swift — see CODE_AUDIT_19 §9.23.

// MARK: - Viewer

public extension ItemControllable {
    func item(for itemId: UUID) async -> Model? {
        await itemDataModel.item(for: itemId) as? Model
    }

    @MainActor func item(for itemId: UUID, fullIds: [UUID], partialIds: [UUID]) async -> Model? {
        guard let model = itemDataModel.item(for: itemId) as? Model else { return nil }
        guard partialIds.contains(itemId) else { return model }
        let partial = model.copy()
        partial.entries = model.entries.filter {
            partialIds.contains($0.childId) || fullIds.contains($0.childId)
        }
        return partial
    }

    @MainActor func item(for itemId: UUID, version: Int) async -> Model? {
        let item = await self.item(for: itemId)
        guard version != 0, let item else { return item }
        return item.version == version ? item : nil
    }
    
    @MainActor func itemSync(for itemId: UUID, noGame: Bool = false) -> Model? {
        itemDataModel.item(for: itemId, noGame: noGame) as? Model
    }

    @MainActor func itemOrEmpty(for itemId: UUID) -> Model {
        guard let item = self.itemSync(for: itemId) else { return Model.empty(itemId) }
        return item
    }
    
    @MainActor func nameSync(itemId: UUID) -> String {
        guard let item = self.itemSync(for: itemId) else { return "" }
        return item.name
    }
    
    /// `loadableUrl` after the file's iCloud download was requested, for an export that hands the
    /// URL to another app: a placeholder that is not downloaded yet would be handed out empty.
    /// A failed download does not stop the export, a file that is local already still exports.
    /// See CODE_AUDIT_28 §6.7.
    @MainActor func downloadedLoadableUrl(itemId: UUID) async -> URL? {
        if let fileUrl = await self.item(for: itemId)?.fileUrl {
            do {
                try await fileUrlDataController?.download(fileUrl: fileUrl)
            } catch is CancellationError {
                return nil
            } catch {
                Logger.itemController.error("Could not download the file before the export: \(error.localizedDescription, privacy: .private)")
            }
        }
        return await loadableUrl(itemId: itemId)
    }

    @MainActor func loadableUrl(itemId: UUID) async -> URL? {
        guard let fileUrl = await self.item(for: itemId)?.fileUrl else { return nil }
        return await fileUrlDataController?.url(for: fileUrl, action: { $0 })
    }
}

// MARK: - Compact Text

public extension ItemControllable {
    /// Returns a compact plain-text representation of the item for AI extraction.
    ///
    /// Default behaviour:
    /// - **Folder / collection** (`specialCategory`): lists visible child names prefixed with "- ".
    /// - **Regular item**: formats as `"<ModuleTitle>: <name>\n\n- entry1\n- entry2…"`.
    ///   Entries with `isGroupHidden` (e.g. MapRPG hex-grid entries) are excluded, and markdown
    ///   links are reduced to their labels.
    ///   Returns `""` when the item has no entries.
    /// - Returns `""` when the item is not found.
    ///
    /// Modules that need custom formatting (e.g. PdfRPG loading file content) can override this.
    @MainActor func compactText(for itemId: UUID) async -> String {
        guard let item = await self.item(for: itemId) else { return "" }
        var lines: [String] = []
        if item.specialCategory {
            for entry in item.entries where !entry.isGroupHidden {
                if let child = await self.item(for: entry.childId), !child.name.isEmpty {
                    lines.append("- \(child.name)")
                }
            }
        } else {
            let visibleEntries = item.entries.filter { !$0.isGroupHidden }
            guard !visibleEntries.isEmpty else { return "" }
            if !item.name.isEmpty {
                lines.append("\(config.module.title): \(item.name)")
                lines.append("")
            }
            // Markdown links are reduced to their labels: the URLs carry nothing the model can use
            // and only eat into its input budget (Character values are mostly links).
            for entry in visibleEntries {
                let name = entry.name.withoutLink()
                let content = entry.content.withoutLink()
                lines.append(content.isEmpty ? "- \(name)" : "- \(name): \(content)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
