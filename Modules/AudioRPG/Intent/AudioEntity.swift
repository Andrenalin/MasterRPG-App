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
            numericFormat: "\(placeholder: .int) audios",
            synonyms: ["Music", "Sound", "Track"]
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: subtitle.isEmpty ? nil : "\(subtitle)",
            image: .init(systemName: icon)
        )
    }

    static let defaultQuery = AudioEntityQuery()

    let id: UUID

    @ComputedProperty(indexingKey: \.displayName)
    var name: String { storedName }

    @ComputedProperty(indexingKey: \.contentDescription)
    var description: String { storedDescription }

    /// The tags of the item, for Shortcuts and the Find action. See CODE_AUDIT_AppIntents §4.5.
    @ComputedProperty
    var tags: [String] { storedTags }

    @ComputedProperty
    var isFolder: Bool { storedIsFolder }

    /// A bounded excerpt of the entries' text, indexed so Spotlight matches words from the body.
    @ComputedProperty(indexingKey: \.textContent)
    var content: String { storedTextContent }

    let icon: String
    /// The folder or the first line of the description, see `IntentEntityText.subtitle`.
    let subtitle: String
    private let storedName: String
    private let storedDescription: String
    private let storedTags: [String]
    private let storedIsFolder: Bool
    private let storedTextContent: String

    var root: AudioRootModel

    // Display fields are captured eagerly: entity properties are nonisolated, the
    // @MainActor model must not be read from them. All queries are @MainActor.
    // `model` itself is intentionally not stored — nothing here reads it after
    // init, and storing it would add a second non-Sendable stored property
    // alongside `root`. See CODE_AUDIT_Audio §3.2.
    @MainActor
    init(root: AudioRootModel, model: AudioModel) {
        self.root = root
        self.id = model.id
        self.storedName = model.name
        self.storedDescription = model.description
        self.storedTags = model.tags
        self.storedIsFolder = model.category == .folder
        self.storedTextContent = IntentEntityText.excerpt(of: model)
        self.subtitle = IntentEntityText.subtitle(of: model) { root.itemController.itemSync(for: $0) }
        let isSpecial = model.category == .folder || model.category.isCollection
        self.icon = isSpecial ? model.category.icon : root.config.module.icon
    }
}

/// Thrown when an `AudioEntity`'s underlying stored audio file can't be
/// resolved to a local file (e.g. the item has no attached file, or the
/// file hasn't finished downloading from iCloud yet).
struct AudioEntityAssetUnavailableError: Error {}

/// The link the app already opens (`RPG://AUDIOS/0/<id>`), so a tapped Spotlight result opens the
/// item on every OS version. The literal must match `URL.appScheme` and
/// `NetworkModules.audio.token`; see `EntityUrlRepresentationTests`.
/// See CODE_AUDIT_AppIntents2 §4.1.
extension AudioEntity: URLRepresentableEntity {
    static var urlRepresentation: URLRepresentation {
        "RPG://AUDIOS/0/\(.id)"
    }
}

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

        DataRepresentation(exportedContentType: .plainText) { @MainActor item in
            EntitySummaryExport.plainText(id: item.id, module: .audio, name: item.name, description: item.description)
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

@available(iOS 27, macOS 27, visionOS 27, *)
extension AudioEntity: SyncableEntity {}

@available(iOS 27, macOS 27, visionOS 27, *)
extension AudioEntityQuery: @preconcurrency IndexedEntityQuery {}
#endif
