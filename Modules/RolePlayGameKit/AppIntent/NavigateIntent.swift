import AppIntents
import CoreRPG
import CoreExternalRPG

@available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
struct NavigateIntent: AppIntent {
    static let title: LocalizedStringResource = "Navigate to Section"

    static let supportedModes: IntentModes = .foreground
    
    static var parameterSummary: some ParameterSummary {
        Summary("Navigate to \(\.$navigationOption)")
    }

    @Parameter(
        title: "Section",
        requestValueDialog: "Which section?"
    )
    var navigationOption: NavigationOption

    @Dependency var appModel: AppModel

    func perform() async throws -> some IntentResult {
        switch navigationOption {
        case .game:
            await appModel.navigator.perform(route: KnownRoutes.game)
        case .adventure:
            await appModel.navigator.perform(route: KnownRoutes.adventures(nil, nil))
        case .character:
            await appModel.navigator.perform(route: KnownRoutes.values(nil, nil))
        case .pdf:
            await appModel.navigator.perform(route: KnownRoutes.pdfs(nil, nil))
        case .table:
            await appModel.navigator.perform(route: KnownRoutes.tables(nil, nil))
        case .map:
            await appModel.navigator.perform(route: KnownRoutes.maps(nil, nil))
        case .photo:
            await appModel.navigator.perform(route: KnownRoutes.photos(nil, nil))
        case .audio:
            await appModel.navigator.perform(route: KnownRoutes.audios(nil, nil))
        case .space:
            await appModel.navigator.perform(route: KnownRoutes.spaces(nil, nil))
        case .weather:
            await appModel.navigator.perform(route: KnownRoutes.weathers(nil, nil))
        case .dice:
            await appModel.navigator.perform(route: KnownRoutes.dice(nil, nil))
        }
        return .result()
    }
}

@available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NavigateIntent {
    init(navigationOption: NavigationOption) {
        self.navigationOption = navigationOption
    }
}

#if os(iOS)
@available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
extension NavigateIntent: TargetContentProvidingIntent {}
#endif
