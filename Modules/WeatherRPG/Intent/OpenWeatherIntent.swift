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

#endif
