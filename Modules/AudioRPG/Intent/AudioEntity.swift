// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import CoreSpotlight
import CoreTransferable
import SwiftUI

struct AudioEntity: IndexedEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Audio"),
            numericFormat: "\(placeholder: .int) audios"
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = AudioEntityQuery()

    let id: UUID

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { storedName }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { storedDescription }

    let icon: String
    private let storedName: String
    private let storedDescription: String

    var root: AudioRootModel
    var model: AudioModel

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    @MainActor
    init(root: AudioRootModel, model: AudioModel) {
        self.root = root
        self.model = model
        self.id = model.id
        self.storedName = model.name
        self.storedDescription = model.description
        let isSpecial = model.category == .folder || model.category.isCollection
        self.icon = isSpecial ? model.category.icon : root.config.module.icon
    }
}

/// Thrown when an `AudioEntity`'s underlying stored audio file can't be
/// resolved to a local file (e.g. the item has no attached file, or the
/// file hasn't finished downloading from iCloud yet).
struct AudioEntityAssetUnavailableError: Error {}

extension AudioEntity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        // Exports the actual stored audio file — matching the fix applied
        // to PdfEntity/PhotoEntity/SpaceEntity (see CODE_AUDIT §5.2); this
        // type previously only offered a plain-text Name/Description export
        // and never attempted a real-file representation at all.
        FileRepresentation(exportedContentType: .mpeg4Audio) { @MainActor item in
            guard let url = await item.root.itemController.loadableUrl(itemId: item.id) else {
                throw AudioEntityAssetUnavailableError()
            }
            return .init(url)
        }

        DataRepresentation(exportedContentType: .plainText) {
            Data(
                """
                Name: \($0.name)
                Description: \($0.description)
                """.utf8
            )
        }
    }
}

// See `ItemEntityQuery`'s own doc for why this is a shared CoreRPG base
// rather than hand-duplicated per module — CODE_AUDIT_10 §9.3.
@MainActor
struct AudioEntityQuery: ItemEntityQuery {
    typealias Entity = AudioEntity
    @Dependency var root: AudioRootModel

    func makeEntity(root: AudioRootModel, model: AudioModel) -> AudioEntity { AudioEntity(root: root, model: model) }
    func allIds(root: AudioRootModel) -> [UUID] { root.itemController.itemDataModel.items }
    func model(root: AudioRootModel, id: UUID) -> AudioModel? { root.itemController.itemSync(for: id) }
}

#if compiler(>=6.4)
@available(iOS 27, macOS 27, visionOS 27, *)
extension AudioEntity: SyncableEntity, OwnershipProvidingEntity {
    var ownership: EntityOwnership { .unknown }
}

@available(iOS 27, macOS 27, visionOS 27, *)
extension AudioEntityQuery: @preconcurrency IndexedEntityQuery {
    func reindexEntities(
        for identifiers: [AudioEntity.ID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let entities = try await entities(for: identifiers)
        try await CSSearchableIndex.default().indexAppEntities(entities)
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        let all = try await allEntities()
        try await CSSearchableIndex.default().indexAppEntities(all)
    }
}
#endif

extension AudioEntity {
    var sharePreview: SharePreview<Never, Image> {
        SharePreview(name, icon: Image(systemName: "music.note.list"))
    }
}

#endif
