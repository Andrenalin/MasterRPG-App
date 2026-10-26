// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents
import Foundation
import os.log
import SwiftUI


struct OpenAudioIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Audio"
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Audio", requestValueDialog: "Which audio?")
    var target: AudioEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.audios(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenAudioIntent: TargetContentProvidingIntent {}
#endif

/// The iOS 27 open intent. `.system.open` lets Siri resolve "open <name> in MasterRPG" against
/// the indexed items; the schema supplies the title and the `target` parameter. It is a sibling
/// of `OpenAudioIntent` (the macro and schema are 27-only, and only one `OpenIntent` may name
/// an entity type) and takes the same route. See CODE_AUDIT_AppIntents §4.2.
@available(iOS 27, macOS 27, visionOS 27, *)
@AppIntent(schema: .system.open)
struct OpenAudioSchemaIntent: OpenIntent {
    var target: AudioEntity

    @Dependency var navigator: Navigator

    init() {}

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.audios(target.id, nil))
        return .result()
    }
}

#if os(iOS)
@available(iOS 27, *)
extension OpenAudioSchemaIntent: TargetContentProvidingIntent {}
#endif

extension AudioRootModel: SiriItemContext {
    public func siriEntityIdentifier(for itemId: UUID) -> EntityIdentifier? {
        EntityIdentifier(for: AudioEntity.self, identifier: itemId)
    }

    public func siriOpenIntent(for itemId: UUID) -> (any AppIntent)? {
        guard let model = itemController.itemSync(for: itemId) else { return nil }
        let entity = AudioEntity(root: self, model: model)
        if #available(iOS 27, macOS 27, visionOS 27, *) {
            let intent = OpenAudioSchemaIntent()
            intent.target = entity
            return intent
        }
        let intent = OpenAudioIntent()
        intent.target = entity
        return intent
    }
}

#endif
