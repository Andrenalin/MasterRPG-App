// @copyright André Trettin

import SwiftUI

enum SingleReviewKind {
    case text
    case tags
    case picker(options: [String])
    case binary
    case sublist
    case link
}

extension SingleReviewKind: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.text, .text), (.binary, .binary), (.sublist, .sublist), (.link, .link): true
        case (.picker(let a), .picker(let b)): a == b
        default: false
        }
    }
}

enum SingleReviewDecision: String, CaseIterable, Identifiable {
    case merge = "Merge"
    case existing = "Existing"
    case imported = "New"

    var id: Self { self }

    var title: String {
        switch self {
        case .merge: String(localized: "Merge", bundle: .module)
        case .existing: String(localized: "Existing", bundle: .module)
        case .imported: String(localized: "New", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
        case .merge: "arrow.triangle.merge"
        case .existing: "clock.arrow.circlepath"
        case .imported: "tray.and.arrow.down"
        }
    }

    var tint: Color {
        switch self {
        case .merge: .blue
        case .existing: .orange
        case .imported: .green
        }
    }

    var tagline: String {
        switch self {
        case .merge: String(localized: "Combine both versions", bundle: .module)
        case .existing: String(localized: "Keep your current data", bundle: .module)
        case .imported: String(localized: "Replace with imported", bundle: .module)
        }
    }
}

@MainActor
final class SingleReviewItem {
    init(existing: (any ItemDataAccessible)?, imported: (any ItemDataAccessible)?, merged: any ItemDataAccessible) {
        self.existing = existing
        self.imported = imported
        self.merged = merged
    }

    let existing: (any ItemDataAccessible)?
    let imported: (any ItemDataAccessible)?
    let merged: any ItemDataAccessible

    func item(for decision: SingleReviewDecision) -> any ItemDataAccessible {
        switch decision {
        case .existing: existing ?? merged
        case .imported: imported ?? merged
        case .merge: merged
        }
    }
}

@MainActor
final class SingleReviewEntry {
    init(existing: (any EntryDataAccessible)?, imported: (any EntryDataAccessible)?, merged: (any EntryDataAccessible)?) {
        self.existing = existing
        self.imported = imported
        self.merged = merged
    }

    let existing: (any EntryDataAccessible)?
    let imported: (any EntryDataAccessible)?
    let merged: (any EntryDataAccessible)?

    func item(for decision: SingleReviewDecision) -> (any EntryDataAccessible)? {
        switch decision {
        case .existing: existing
        case .imported: imported
        case .merge: merged
        }
    }

    var hasDifferences: Bool {
        switch (existing, imported) {
        case (nil, nil):
            false
        case (.some, nil), (nil, .some):
            true
        case let (.some(existing), .some(imported)):
            !entriesAreSemanticallySame(existing, imported)
        }
    }
}

@MainActor
private func entriesAreSemanticallySame(
    _ existing: any EntryDataAccessible,
    _ imported: any EntryDataAccessible
) -> Bool {
    if let comparable = existing as? any ItemDiffComparable,
       let isSame = compareEntry(comparable, with: imported) {
        return isSame
    }

    return compareBasicEntry(existing, with: imported) ?? false
}

@MainActor
private func compareEntry<Entry: ItemDiffComparable>(
    _ existing: Entry,
    with imported: any EntryDataAccessible
) -> Bool? {
    guard let imported = imported as? Entry else { return nil }
    return existing.isSame(imported)
}

private func compareBasicEntry<Entry: EntryDataAccessible>(
    _ existing: Entry,
    with imported: any EntryDataAccessible
) -> Bool? {
    guard let imported = imported as? Entry else { return nil }
    return existing.name == imported.name && existing.content == imported.content
}

@Observable @MainActor
final class SingleReviewItemProperty: Identifiable {
    init(
        id: UUID,
        item: SingleReviewItem,
        displayName: String,
        kind: SingleReviewKind,
        value: @escaping @MainActor (any ItemDataAccessible) -> String,
        compareValue: (@MainActor (any ItemDataAccessible) -> String)? = nil,
        reviewValue: (@MainActor (any ItemDataAccessible) -> ReviewPropertyValue)? = nil,
        isReadOnly: Bool = false,
        decision: SingleReviewDecision,
        apply: @escaping @MainActor (inout any ItemDataAccessible, any ItemDataAccessible) -> Void
    ) {
        self.id = id
        self.item = item
        self.displayName = displayName
        self.kind = kind
        self.value = value
        self.compareValue = compareValue ?? value
        self.reviewValue = reviewValue
        self.isReadOnly = isReadOnly
        self.decision = decision
        self.apply = apply
    }

    let id: UUID
    let item: SingleReviewItem
    let displayName: String
    let kind: SingleReviewKind
    let value: @MainActor (any ItemDataAccessible) -> String
    let compareValue: @MainActor (any ItemDataAccessible) -> String
    let reviewValue: (@MainActor (any ItemDataAccessible) -> ReviewPropertyValue)?
    let isReadOnly: Bool
    let apply: @MainActor (inout any ItemDataAccessible, any ItemDataAccessible) -> Void

    var decision: SingleReviewDecision

    var supportsMerge: Bool { kind != .binary }

    var availableDecisions: [SingleReviewDecision] {
        supportsMerge ? SingleReviewDecision.allCases : [.existing, .imported]
    }
}

@Observable @MainActor
final class SingleReviewEntryProperty: Identifiable {
    init(
        id: UUID,
        entry: SingleReviewEntry,
        displayName: String,
        kind: SingleReviewKind,
        valueKeyPath: KeyPath<any EntryDataAccessible, String>,
        decision: SingleReviewDecision,
        apply: @escaping (inout any EntryDataAccessible, any EntryDataAccessible) -> Void
    ) {
        self.id = id
        self.entry = entry
        self.displayName = displayName
        self.kind = kind
        self.valueKeyPath = valueKeyPath
        self.decision = decision
        self.apply = apply
    }

    let id: UUID
    let entry: SingleReviewEntry
    let displayName: String
    let kind: SingleReviewKind
    let valueKeyPath: KeyPath<any EntryDataAccessible, String>
    let apply: (inout any EntryDataAccessible, any EntryDataAccessible) -> Void

    var decision: SingleReviewDecision

    var supportsMerge: Bool { kind != .binary }

    var availableDecisions: [SingleReviewDecision] {
        supportsMerge ? SingleReviewDecision.allCases : [.existing, .imported]
    }
}

@Observable @MainActor
final class SingleReviewReference: Identifiable {
    enum Status {
        case resolved
        case pendingImport
        case missing
    }

    init(itemName: String, destination: ItemRowModel, existsInLibrary: Bool, pendingItem: ImportReviewItemModel? = nil) {
        self.itemName = itemName
        self.destination = destination
        self.existsInLibrary = existsInLibrary
        self.pendingItem = pendingItem
        self.fixedStatus = nil
    }

    init(itemName: String, destination: ItemRowModel, status: Status) {
        self.itemName = itemName
        self.destination = destination
        self.existsInLibrary = status == .resolved
        self.pendingItem = nil
        self.fixedStatus = status
    }

    let id = UUID()
    let itemName: String
    let destination: ItemRowModel
    let existsInLibrary: Bool
    weak var pendingItem: ImportReviewItemModel?
    private let fixedStatus: Status?

    var module: NetworkModules { destination.typeId }
    var moduleName: String { destination.typeId.title }

    var status: Status {
        if let fixedStatus { return fixedStatus }
        if let pendingItem {
            if pendingItem.isDeletion {
                return pendingItem.itemModel.decision == .imported ? .missing : (existsInLibrary ? .resolved : .missing)
            }
            if pendingItem.itemModel.decision != .existing { return .pendingImport }
        }
        return existsInLibrary ? .resolved : .missing
    }

    var isResolved: Bool { status == .resolved }
}

