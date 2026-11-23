// @copyright André Trettin

#if !os(tvOS)

import AppIntents
import CoreSpotlight
import Foundation
import os.log
import UniformTypeIdentifiers

// Helpers every module's `*ManagementIntents.swift` shares: parameter text, the database gate,
// optional file intake, required name and target, and the App Entity index calls (index, delete,
// trash, incremental reindex). They carry no per-module behavior. What does differ per module
// (the `Entity` struct, its `EntityQuery`, `Transferable` and `attributeSet`) stays in each
// module's `*Entity.swift`; `ItemEntityQuery` holds only the query skeleton they share.

/// A rich-text intent parameter as the Markdown the app stores, or an empty string when none was
/// passed. Text from Shortcuts' Use Model action arrives with bold, italics, links, headings and
/// lists; dropping them flattened a model-written section into one paragraph. Foundation has no
/// `AttributedString` → Markdown writer, so the presentation intents are mapped here: inline
/// emphasis, code and links per run, headings, list items and quotes per block.
/// See CODE_AUDIT_AppIntents3 §4.15.
public func intentMarkdown(from text: AttributedString?) -> String {
    guard let text else { return "" }
    var blocks: [(intent: PresentationIntent?, text: String)] = []
    for run in text.runs {
        let piece = markdownInline(String(text[run.range].characters), run: run)
        if let last = blocks.last, last.intent == run.presentationIntent {
            blocks[blocks.count - 1].text += piece
        } else {
            blocks.append((run.presentationIntent, piece))
        }
    }
    var result = ""
    var previousList: Int?
    for block in blocks {
        let list = listIdentity(of: block.intent)
        if !result.isEmpty {
            result += (list != nil && list == previousList) ? "\n" : "\n\n"
        }
        result += markdownBlock(block.text, intent: block.intent)
        previousList = list
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func markdownInline(_ text: String, run: AttributedString.Runs.Run) -> String {
    let core = text.trimmingCharacters(in: .whitespaces)
    guard !core.isEmpty else { return text }
    var marked = core
    if let inline = run.inlinePresentationIntent {
        if inline.contains(.code) { marked = "`\(marked)`" }
        if inline.contains(.stronglyEmphasized) { marked = "**\(marked)**" }
        if inline.contains(.emphasized) { marked = "*\(marked)*" }
        if inline.contains(.strikethrough) { marked = "~~\(marked)~~" }
    }
    if let link = run.link {
        marked = "[\(LinkBuilder.escapedLabel(marked))](\(link.absoluteString))"
    }
    guard marked != core else { return text }
    let leading = text.prefix { $0 == " " }
    let trailing = String(text.reversed().prefix { $0 == " " })
    return "\(leading)\(marked)\(trailing)"
}

private func markdownBlock(_ text: String, intent: PresentationIntent?) -> String {
    guard let components = intent?.components else { return text }
    var prefix = ""
    for component in components.reversed() {
        switch component.kind {
        case .header(let level):
            prefix += String(repeating: "#", count: level) + " "
        case .listItem(let ordinal):
            let isOrdered = components.contains { if case .orderedList = $0.kind { true } else { false } }
            prefix += isOrdered ? "\(ordinal). " : "- "
        case .blockQuote:
            prefix += "> "
        default:
            break
        }
    }
    return prefix + text.trimmingCharacters(in: .newlines)
}

/// The identity of the list a block belongs to, so consecutive items stay on adjacent lines.
private func listIdentity(of intent: PresentationIntent?) -> Int? {
    intent?.components.first { component in
        switch component.kind {
        case .orderedList, .unorderedList: true
        default: false
        }
    }?.identity
}

/// `original` with `addition` added as a new paragraph. A blank addition changes nothing, and a
/// blank original is replaced instead of keeping leading blank lines.
public func appendingIntentText(_ addition: String, to original: String) -> String {
    let trimmedAddition = addition.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedAddition.isEmpty else { return original }

    let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedOriginal.isEmpty else { return trimmedAddition }

    return "\(trimmedOriginal)\n\n\(trimmedAddition)"
}

/// Thrown by an intent that writes when the database did not start in time, so the user hears
/// that nothing was saved instead of "Created". See CODE_AUDIT §5.1.
public struct DatabaseNotReadyError: Error, CustomLocalizedStringResourceConvertible {
    public var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(
            "MasterRPG is not ready yet. Open the app and try again.",
            bundle: .module,
            comment: "Error shown by Siri or Shortcuts when the database did not start in time."
        )
    }
}

/// Waits for the database like `DatabaseReadiness.wait()` and throws `DatabaseNotReadyError` when
/// it still cannot take writes after the timeout. Every intent that creates, changes or deletes
/// items starts with this; read-only intents may keep using `DatabaseReadiness.wait()`.
/// A cancelled intent (the user dismissed Siri while it waited) throws `CancellationError`
/// instead of writing once the store is ready. See CODE_AUDIT §5.1, CODE_AUDIT_Since_3.0.1 §3.4.
@MainActor
public func requireReadyDatabase() async throws {
    let canSave = await DatabaseReadiness.wait()
    try Task.checkCancellation()
    guard canSave else { throw DatabaseNotReadyError() }
}

/// Thrown by an intent whose save failed (full disk, broken store), so Siri does not confirm a
/// change that is not on disk. The app's persistence banner says why. See CODE_AUDIT_Since_3.0.1 §5.5.
public struct IntentSaveError: Error, CustomLocalizedStringResourceConvertible {
    public init() {}

    public var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(
            "The change could not be saved. Open MasterRPG to see why.",
            bundle: .module,
            comment: "Error shown by Siri or Shortcuts when an intent changed an item but saving it failed."
        )
    }
}

public extension ItemControllable {
    /// `save()` for an App Intent: throws `IntentSaveError` when the save failed. `save()` records
    /// a failure in `lastPersistenceError` and clears it on success, so the check reads this
    /// save's outcome. Every intent that writes saves through here. See CODE_AUDIT_Since_3.0.1 §5.5.
    @MainActor func saveForIntent() async throws {
        await save()
        guard itemDataModel.lastPersistenceError == nil else { throw IntentSaveError() }
    }
}

/// Thrown by an intent that would change an item loaded into the current game, so Siri says why
/// instead of reporting a change that would be lost. See CODE_AUDIT_Since_3.0.1 §5.2.
public struct ItemInGameError: Error, CustomLocalizedStringResourceConvertible {
    public init() {}

    public var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(
            "This is part of the current game. Change it after the game has ended.",
            bundle: .module,
            comment: "Error shown by Siri or Shortcuts when an intent would change an item the running game uses."
        )
    }
}

/// Intents write to the library, also while a game runs: every intent write passes
/// `forceSave: true`. Without it a write during a game only reached game memory, was gone when the
/// game ended, and Siri still said "Created" or "Updated". An item the game has loaded (it has a
/// game copy) is refused instead: its copy holds session state such as hit points or revealed
/// rooms, which a library write must neither take over nor overwrite. Throws `ItemInGameError`.
/// See CODE_AUDIT_Since_3.0.1 §5.2.
@MainActor
public func requireOutsideGame(_ ids: [UUID], in itemDataModel: ItemDataModel) throws {
    guard !ids.contains(where: { itemDataModel.gameItemData[$0] != nil }) else { throw ItemInGameError() }
}

/// `requireOutsideGame(_:in:)` for the items of a module root.
@MainActor
public func requireOutsideGame(_ ids: [UUID], in root: some ItemRootControllable) throws {
    try requireOutsideGame(ids, in: root.itemControllable.itemDataModel)
}

/// The file passed to a Create intent has a type the item cannot hold.
public struct IntentFileTypeError: Error, CustomLocalizedStringResourceConvertible {
    public init() {}

    public var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(
            "The file is not a type this item can hold.",
            bundle: .module,
            comment: "Error shown by Siri or Shortcuts when the file passed to a Create intent has the wrong type."
        )
    }
}

/// The file passed to a Create intent is larger than the app opens on behalf of an item.
public struct IntentFileSizeError: Error, CustomLocalizedStringResourceConvertible {
    public init() {}

    public var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(
            "The file is too large.",
            bundle: .module,
            comment: "Error shown by Siri or Shortcuts when the file passed to a Create intent is larger than the size limit."
        )
    }
}

/// The file passed to a Create intent could not be stored with the new item.
public struct IntentFileStoreError: Error, CustomLocalizedStringResourceConvertible {
    public init() {}

    public var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(
            "The file could not be added.",
            bundle: .module,
            comment: "Error shown by Siri or Shortcuts when the file passed to a Create intent could not be stored."
        )
    }
}

/// The bytes of the optional file parameter of a Create intent, or `nil` when none was passed.
/// Throws `IntentFileTypeError` before anything is created when the file is not one of the types
/// the module holds, so a wrong file leaves no empty item behind. The bytes are read off the
/// caller's actor: a Create intent runs on the main actor, and the file can be a large audio,
/// PDF or USDZ file. See CODE_AUDIT_AppIntents2 §4.4, CODE_AUDIT_Since_3.0.1 §3.2.
///
/// A file above `maximumBytes` throws `IntentFileSizeError`. A file on disk is measured before it
/// is read, so a huge file is never loaded into memory; bytes the caller passed in memory are
/// measured as they are. See CODE_AUDIT_26 §6.10.
public func intentFileData(
    _ file: IntentFile?,
    allowedTypes: [UTType],
    maximumBytes: Int = ByteLimits.maximumSourceFileBytes
) async throws -> Data? {
    guard let file else { return nil }
    let type = file.type ?? UTType(filenameExtension: URL(filePath: file.filename).pathExtension)
    guard let type, allowedTypes.contains(where: { type.conforms(to: $0) }) else {
        throw IntentFileTypeError()
    }
    return try await runOffCallerExecutor { () throws -> Data in
        if let url = file.fileURL,
           let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > maximumBytes {
            throw IntentFileSizeError()
        }
        let data = file.data
        guard data.count <= maximumBytes else { throw IntentFileSizeError() }
        return data
    }
}

/// Stores the file of a just-created item through `store`, which reports whether it worked. When it
/// did not, the item is removed again and `IntentFileStoreError` is thrown: a media item without
/// its media is not what the user asked for.
@MainActor
public func attachIntentFile<Controller: EditControllable>(
    to itemId: UUID,
    editControllable: Controller,
    store: () async throws -> Bool
) async throws {
    let stored = (try? await store()) ?? false
    guard stored, editControllable.editModel(for: itemId)?.fileUrl != nil else {
        await editControllable.delete(itemId: itemId)
        throw IntentFileStoreError()
    }
}

/// A name or title from Siri or Shortcuts, trimmed. Both can pass an empty or all-whitespace
/// string, so a blank one asks for the value again instead of creating a nameless item or entry.
/// See CODE_AUDIT_AppIntents §5.2.
public func requiredIntentName(
    _ text: String,
    parameter: IntentParameter<String>,
    prompt: IntentDialog
) throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw parameter.needsValueError(prompt) }
    return trimmed
}

/// `labels` for a Siri or Shortcuts disambiguation, each one unique: a repeated label gets its
/// count, "HP", "HP (2)". The choice comes back as a string, so with repeated labels the second
/// one could never be picked. The order and the count stay, so an index still maps back to the
/// source. See CODE_AUDIT_Since_3.0.1 §5.18.
public func uniqueIntentLabels(_ labels: [String]) -> [String] {
    var seen: [String: Int] = [:]
    var used = Set(labels)
    return labels.map { label in
        let count = seen[label, default: 0] + 1
        seen[label] = count
        guard count > 1 else { return label }
        var number = count
        var unique = "\(label) (\(number))"
        while used.contains(unique) {
            number += 1
            unique = "\(label) (\(number))"
        }
        used.insert(unique)
        return unique
    }
}

/// The model behind an entity parameter. The entity can be stale — deleted since Siri or
/// Shortcuts cached it — so a missing model asks for the target again instead of reporting a
/// success that changed nothing. See CODE_AUDIT_AppIntents §5.2.
@discardableResult
public func requiredIntentTarget<Entity: AppEntity, Model>(
    _ model: Model?,
    parameter: IntentParameter<Entity>,
    prompt: IntentDialog
) throws -> Model {
    guard let model else { throw parameter.needsValueError(prompt) }
    return model
}

/// What every Update intent does: renames the item, replaces its description and adds or removes
/// tags, each only when the intent was given a value (an omitted parameter keeps the field, an
/// empty description clears it, an empty name is ignored because an item needs one). Saves once
/// and reports whether anything changed. An item the current game uses is refused with
/// `ItemInGameError`. See CODE_AUDIT_AppIntents3 §4.5, CODE_AUDIT_Since_3.0.1 §5.2.
@MainActor
@discardableResult
public func updateIntentItem(
    id: UUID,
    name: String?,
    description: AttributedString?,
    addTags: [String]?,
    removeTags: [String]?,
    in root: some ItemRootControllable
) async throws -> Bool {
    try requireOutsideGame([id], in: root)
    let edit = root.editControllable
    guard let model = edit.editModel(for: id) else { return false }
    var changed = false

    if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name != model.name {
        edit.reset(name: name, itemId: id, forceSave: true)
        changed = true
    }
    if let description {
        let text = intentMarkdown(from: description)
        if text != model.description {
            edit.reset(description: text, itemId: id, forceSave: true)
            changed = true
        }
    }

    let removed = Set((removeTags ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    var tags = model.tags.filter { !removed.contains($0.lowercased()) }
    for tag in addTags ?? [] {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { continue }
        tags.append(trimmed)
    }
    if Set(tags) != Set(model.tags) {
        edit.reset(tags: tags, itemId: id, forceSave: true)
        changed = true
    }

    if changed {
        try await root.itemControllable.saveForIntent()
    }
    return changed
}

/// Indexes entities right after an intent saved them, so a follow-up Siri request finds them. The
/// item is already saved and the invalidator indexes it anyway, so a failing index is logged and
/// does not fail the intent (a retry of a "failed" create would make a duplicate).
/// See CODE_AUDIT §5.3.
public func indexIntentEntities<Entity: IndexedEntity>(_ entities: [Entity]) async {
    guard CSSearchableIndex.isIndexingAvailable(), !entities.isEmpty else { return }
    do {
        try await CSSearchableIndex.default().indexAppEntities(entities)
    } catch {
        Logger.appIntents.error("Indexing \(entities.count, privacy: .public) \(String(describing: Entity.self), privacy: .public) failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
    }
}

/// Removes entities from the Spotlight index. A failing index must not fail what the user asked
/// for (the item is already trashed and saved), so the error is logged and the call returns.
/// See CODE_AUDIT_AppIntents §5.8.
public func deleteIntentEntities<Entity: IndexedEntity>(
    ids: [UUID],
    ofType entityType: Entity.Type
) async where Entity.ID == UUID {
    guard CSSearchableIndex.isIndexingAvailable(), !ids.isEmpty else { return }

    do {
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            try await CSSearchableIndex.default().deleteAppEntities(
                identifiedBy: ids,
                ofType: entityType
            )
        } else {
            try await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids.map(\.uuidString))
        }
    } catch {
        Logger.appIntents.error("Removing \(ids.count, privacy: .public) \(String(describing: entityType), privacy: .public) from the Spotlight index failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
    }
}

/// What every Delete intent does: moves the items to the trash, saves, and takes them out of the
/// Spotlight index. A folder takes everything below it along, as the delete in the list does;
/// trashing only the folder left its children live under a trashed parent. The trash is
/// recoverable, and the dialog stays with the intent because each module localizes it from its own
/// bundle. Nothing is trashed when one of the items is used by the current game
/// (`ItemInGameError`). See CODE_AUDIT_AppIntents §9.3, CODE_AUDIT_Since_3.0.1 §5.2, §5.4.
@MainActor
public func trashIntentItems<Entity: IndexedEntity>(
    ids: [UUID],
    ofType entityType: Entity.Type,
    in root: some ItemRootControllable
) async throws where Entity.ID == UUID {
    let module = root.itemControllable.config.module
    let removing = root.editControllable
        .collectionItemsForRemoval(for: ids.map { ItemRowModel(itemId: $0, typeId: module) })
        .map(\.itemId)
    try requireOutsideGame(removing, in: root)
    for id in removing {
        root.editControllable.markForDeletion(itemId: id, forceSave: true)
    }
    try await root.itemControllable.saveForIntent()
    await deleteIntentEntities(ids: removing, ofType: entityType)
}

/// Brings the module's App Entity index up to date with what changed since the last run: the ids
/// `itemDataModel` marked (edited, trashed, removed) and the ids added or removed since the
/// `ledger` last saw them are indexed again, and the ones whose item is gone, trashed or not
/// `isIndexable` (e.g. the rule compendium's own categories) leave the index, because the queries
/// hide them and Siri would find an item it cannot open. A run without changes, including the
/// first one after a launch, does nothing. The first run per module (no ledger list yet) covers
/// every item and also clears what earlier versions left in the index (everything of the type on
/// iOS 27). Trashing and purging in the UI additionally remove entries at once
/// (`IntentEntityIdentifiers.removeFromIndex`). A run waits while a module's initial load is
/// still running: its ids would look removed. See CODE_AUDIT_AppIntents §5.3, §7.1,
/// CODE_AUDIT_Since_3.0.1 §3.1.
@MainActor
public func reindexIntentEntities<Entity: IndexedEntity, Model: ItemDataAccessible>(
    itemDataModel: ItemDataModel,
    module: NetworkModules,
    ledger: AppEntityIndexLedger = .shared,
    model: (UUID) -> Model?,
    isIndexable: (Model) -> Bool = { _ in true },
    makeEntity: (Model) -> Entity
) async where Entity.ID == UUID {
    guard CSSearchableIndex.isIndexingAvailable() else { return }
    // The last initial load calls the invalidator when it ends, so the marks wait for that run.
    guard InitialLoadTracker.shared.isIdle else { return }

    let indexed = await ledger.indexedIds(for: module.token)
    let needsPrune = indexed == nil
    let current = Set(itemDataModel.items)
    let changedIds = itemDataModel.takeIndexDirtyIds()
    let looked = AppEntityIndexPass.ids(current: current, changed: changedIds, indexed: indexed)
    guard !looked.isEmpty || needsPrune else { return }
    let ids = Array(looked)

    var entities: [Entity] = []
    var notIndexed: [UUID] = []
    for id in ids {
        if let model = model(id), !model.isHidden, isIndexable(model) {
            entities.append(makeEntity(model))
        } else {
            notIndexed.append(id)
        }
    }

    if needsPrune {
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            do {
                try await CSSearchableIndex.default().deleteAppEntities(ofType: Entity.self)
            } catch {
                Logger.appIntents.error("Clearing the \(module.token, privacy: .public) App Entity index failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                // No ledger list is written, so the next run prunes again; the changes are kept for it.
                changedIds.forEach(itemDataModel.markIndexDirty)
                return
            }
        }
    }

    await deleteIntentEntities(ids: notIndexed, ofType: Entity.self)

    var failed: Set<UUID> = []
    do {
        try await CSSearchableIndex.default().indexAppEntities(entities)
    } catch {
        Logger.appIntents.error("\(module.token, privacy: .public) reindex failed: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        // Left marked, so the next run indexes them again, and out of the ledger for the next launch.
        failed = Set(entities.map(\.id))
        failed.forEach(itemDataModel.markIndexDirty)
    }
    await ledger.setIndexedIds(
        AppEntityIndexPass.indexed(before: indexed, looked: looked, failed: failed, current: current),
        for: module.token
    )
}

#endif
