// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import AppIntents

import Foundation
import SwiftUI

struct OpenWeatherIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Weather"

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

extension WeatherRootModel {
    @MainActor
    func addSiriContext(to activity: NSUserActivity, itemId: UUID) {
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }
        activity.appEntityIdentifier = EntityIdentifier(for: WeatherEntity.self, identifier: itemId)
#endif
    }

    @MainActor
    func donateSiriViewingIntent(for itemId: UUID) async {
#if compiler(>=6.4)
        guard #available(iOS 27, macOS 27, visionOS 27, *),
              let model = itemController.itemSync(for: itemId)
        else { return }

        var intent = OpenWeatherIntent()
        intent.target = WeatherEntity(root: self, model: model)
        do {
            try await IntentDonationManager.shared.donate(intent: intent)
        } catch {}
#endif
    }
}

#endif
