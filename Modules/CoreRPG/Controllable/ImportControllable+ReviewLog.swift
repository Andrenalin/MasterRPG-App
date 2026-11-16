// @copyright André Trettin

import Foundation
import os.log


/// The import log, to ask whether info-level messages are recorded before building one that is
/// expensive to build. See CODE_AUDIT_21 §7.2.
private let importReviewLog = OSLog(subsystem: Logger.subsystem, category: "ImportController")

extension ImportControllable {
    @MainActor
    func logManualReviewDifference(
        module: NetworkModules,
        id: UUID,
        existing: (any ItemDataAccessible)?,
        imported: any ItemDataAccessible,
        itemModel: SingleItemImportModel
    ) {
        guard let existing else {
            Logger.importController.info("Manual import review added \(module.token, privacy: .public) id=\(id.uuidString, privacy: .public) name='\(imported.name.importLogPreview, privacy: .private)'")
            return
        }

        // The summary below compares every property and entry again, only to be logged at the
        // info level. See CODE_AUDIT_21 §7.2.
        guard importReviewLog.isEnabled(type: .info) else { return }
        let reviewDifferences = reviewPropertyDifferences(in: itemModel) + reviewEntryDifferences(in: itemModel)
        let commonDifferences = commonItemDifferences(existing: existing, imported: imported)
        let reviewSummary = reviewDifferences.importLogSummary
        let commonSummary = commonDifferences.importLogSummary

        if reviewDifferences.isEmpty && commonDifferences.isEmpty {
            Logger.importController.warning("Manual import review different \(module.token, privacy: .public) id=\(id.uuidString, privacy: .public) name='\(imported.name.importLogPreview, privacy: .private)' but review/common fields match. model.isSame returned false; likely CRDT update metadata or module-specific fields not exposed in reviewProperties.")
        } else {
            // User-authored sheet content — imported item/entry field values — defaults to
            // `.private` here (unlike the enum/identifier fields alongside it), matching the
            // project's logging privacy convention. This is the highest-content-volume site of
            // that gap: unredacted excerpts of imported character sheets, adventure notes, or
            // campaign content previously persisted in plaintext system logs during ordinary
            // (non-DEBUG-gated) import review. See CODE_AUDIT §6.4.
            Logger.importController.info("Manual import review different \(module.token, privacy: .public) id=\(id.uuidString, privacy: .public) name='\(imported.name.importLogPreview, privacy: .private)' reviewRows=\(reviewSummary, privacy: .private) commonFields=\(commonSummary, privacy: .private)")
        }
    }

    @MainActor
    func logManualReviewUnchangedSkipped(module: NetworkModules, id: UUID, imported: any ItemDataAccessible) {
        Logger.importController.info("Manual import review unchanged skipped \(module.token, privacy: .public) id=\(id.uuidString, privacy: .public) name='\(imported.name.importLogPreview, privacy: .private)' because merge returned nil (model.isSame == true).")
    }

    @MainActor
    func reviewPropertyDifferences(in itemModel: SingleItemImportModel) -> [String] {
        itemModel.properties.compactMap { property in
            guard itemModel.isChanged(prop: property) else { return nil }
            return "property '\(property.displayName)': existing='\((itemModel.existingValue(for: property) ?? "nil").importLogPreview)' imported='\((itemModel.importedValue(for: property) ?? "nil").importLogPreview)' merged='\((itemModel.mergedValue(for: property) ?? "nil").importLogPreview)'"
        }
    }

    @MainActor
    func reviewEntryDifferences(in itemModel: SingleItemImportModel) -> [String] {
        itemModel.entries.flatMap { entryModel in
            let entryLabel = "\(entryModel.name.importLogPreview) (\(entryModel.id.uuidString))"

            if entryModel.entry.existing == nil {
                return ["entry added '\(entryLabel)'"]
            }
            if entryModel.entry.imported == nil {
                return ["entry missing from import '\(entryLabel)'"]
            }

            return entryModel.properties.compactMap { property in
                guard entryModel.isChanged(prop: property) else { return nil }
                return "entry '\(entryLabel)' property '\(property.displayName)': existing='\((entryModel.existingValue(for: property) ?? "nil").importLogPreview)' imported='\((entryModel.importedValue(for: property) ?? "nil").importLogPreview)' merged='\((entryModel.mergedValue(for: property) ?? "nil").importLogPreview)'"
            }
        }
    }

    @MainActor
    func commonItemDifferences(existing: any ItemDataAccessible, imported: any ItemDataAccessible) -> [String] {
        var differences: [String] = []

        appendImportDifference("id", existing.id.uuidString, imported.id.uuidString, to: &differences)
        appendImportDifference("name", existing.name, imported.name, to: &differences)
        appendImportDifference("description", existing.description, imported.description, to: &differences)
        appendImportDifference("tags", existing.tags.joined(separator: ","), imported.tags.joined(separator: ","), to: &differences)
        appendImportDifference("category", "\(existing.category.rawValue)", "\(imported.category.rawValue)", to: &differences)
        appendImportDifference("displayState", "\(existing.displayState)", "\(imported.displayState)", to: &differences)
        appendImportDifference("isGroupHiddenToggle", "\(existing.isGroupHiddenToggle)", "\(imported.isGroupHiddenToggle)", to: &differences)
        appendImportDifference("parentId", existing.parentId?.uuidString ?? "nil", imported.parentId?.uuidString ?? "nil", to: &differences)
        differences += fileDifferences(existing: existing.fileUrl, imported: imported.fileUrl)
        differences += entryDifferences(existing: existing.entries, imported: imported.entries)

        return differences
    }

    func fileDifferences(existing: FileUrl?, imported: FileUrl?) -> [String] {
        var differences: [String] = []
        appendImportDifference("file.id", existing?.fileId.uuidString ?? "nil", imported?.fileId.uuidString ?? "nil", to: &differences)
        appendImportDifference("file.url", existing?.rawUrl.absoluteString ?? "nil", imported?.rawUrl.absoluteString ?? "nil", to: &differences)
        appendImportDifference("file.location", existing.map { "\($0.location)" } ?? "nil", imported.map { "\($0.location)" } ?? "nil", to: &differences)
        appendImportDifference("file.module", existing?.module ?? "nil", imported?.module ?? "nil", to: &differences)
        appendImportDifference("file.contentHash", existing?.contentHash ?? "nil", imported?.contentHash ?? "nil", to: &differences)
        return differences
    }

    func entryDifferences(existing: [any EntryDataAccessible], imported: [any EntryDataAccessible]) -> [String] {
        var differences: [String] = []
        let existingIds = existing.map(\.id)
        let importedIds = imported.map(\.id)
        appendImportDifference("entry.ids", existingIds.map(\.uuidString).joined(separator: ","), importedIds.map(\.uuidString).joined(separator: ","), to: &differences)

        // Indexed by id, see `SingleItemImportModel.from(item:)`. See CODE_AUDIT_21 §7.2.
        var seenIds: Set<UUID> = []
        let allIds = (existingIds + importedIds).filter { seenIds.insert($0).inserted }
        let existingById = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let importedById = Dictionary(imported.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for id in allIds {
            let existingEntry = existingById[id]
            let importedEntry = importedById[id]
            let entryPrefix = "entry \(id.uuidString)"

            guard let existingEntry, let importedEntry else {
                appendImportDifference("\(entryPrefix).presence", existingEntry == nil ? "missing" : "present", importedEntry == nil ? "missing" : "present", to: &differences)
                continue
            }

            appendImportDifference("\(entryPrefix).childId", existingEntry.childId.uuidString, importedEntry.childId.uuidString, to: &differences)
            appendImportDifference("\(entryPrefix).name", existingEntry.name, importedEntry.name, to: &differences)
            appendImportDifference("\(entryPrefix).content", existingEntry.content, importedEntry.content, to: &differences)
            appendImportDifference("\(entryPrefix).displayState", "\(existingEntry.displayState)", "\(importedEntry.displayState)", to: &differences)
        }

        return differences
    }

    func appendImportDifference(_ label: String, _ existing: String, _ imported: String, to differences: inout [String]) {
        guard existing != imported else { return }
        differences.append("\(label): existing='\(existing.importLogPreview)' imported='\(imported.importLogPreview)'")
    }
}

private extension Array where Element == String {
    var importLogSummary: String {
        guard !isEmpty else { return "none" }
        let maxItems = 16
        let visibleItems = prefix(maxItems)
        let summary = visibleItems.joined(separator: " | ")
        let remainingCount = count - visibleItems.count
        guard remainingCount > 0 else { return summary }
        return "\(summary) | +\(remainingCount) more"
    }
}

private extension String {
    var importLogPreview: String {
        let maxLength = 240
        let flattened = trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing("\n", with: "\\n")
            .replacing("\r", with: "\\r")
        guard flattened.count > maxLength else { return flattened }
        return "\(String(flattened.prefix(maxLength)))..."
    }
}
