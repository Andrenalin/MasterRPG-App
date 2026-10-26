// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

import Foundation
import os.log
import SwiftUI

struct OpenWeatherIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Weather"
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Weather", requestValueDialog: "Which Weather?")
    var target: WeatherEntity

    @Dependency var navigator: Navigator

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.weathers(target.id, nil))
        return .result()
    }
}

#if os(iOS)
extension OpenWeatherIntent: TargetContentProvidingIntent {}
#endif

/// The iOS 27 open intent. `.system.open` lets Siri resolve "open <name> in MasterRPG" against
/// the indexed items; the schema supplies the title and the `target` parameter. It is a sibling
/// of `OpenWeatherIntent` (the macro and schema are 27-only, and only one `OpenIntent` may name
/// an entity type) and takes the same route. See CODE_AUDIT_AppIntents §4.2.
@available(iOS 27, macOS 27, visionOS 27, *)
@AppIntent(schema: .system.open)
struct OpenWeatherSchemaIntent: OpenIntent {
    var target: WeatherEntity

    @Dependency var navigator: Navigator

    init() {}

    func perform() async throws -> some IntentResult {
        await navigator.perform(route: KnownRoutes.weathers(target.id, nil))
        return .result()
    }
}

#if os(iOS)
@available(iOS 27, *)
extension OpenWeatherSchemaIntent: TargetContentProvidingIntent {}
#endif

extension WeatherRootModel {
    @MainActor
    /// `appEntityIdentifier` is available since iOS 18.2 / macOS 15.2 / visionOS 2.2, so it needs no
    /// iOS 27 gate. See CODE_AUDIT_AppIntents §5.1.
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
        activity.appEntityIdentifier = EntityIdentifier(for: WeatherEntity.self, identifier: itemId)
    }

    @MainActor
    /// Donates the open intent that matches the running OS, once the item stays selected.
    /// See CODE_AUDIT_AppIntents §4.4.
    func donateSiriViewingIntent(for itemId: UUID) async {
        await IntentDonations.donateOpen(of: itemId) { [self] () -> (any AppIntent)? in
            guard let model = itemController.itemSync(for: itemId) else { return nil }
            let entity = WeatherEntity(root: self, model: model)
            if #available(iOS 27, macOS 27, visionOS 27, *) {
                let intent = OpenWeatherSchemaIntent()
                intent.target = entity
                return intent
            }
            let intent = OpenWeatherIntent()
            intent.target = entity
            return intent
        }
    }
}

#endif
