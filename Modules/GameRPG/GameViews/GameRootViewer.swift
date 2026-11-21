// @copyright André Trettin

import CoreRPG
import SwiftUI
import MapRPG
import WeatherRPG
import TableRPG
import SpaceRPG
import PhotoRPG
import PdfRPG

enum GameMapContentType: Hashable {
    case master, player, externalPlayer

    /// Keep an external player display on its role-correct 2D renderer. A
    /// RealityKit entity hierarchy can only be attached to one RealityView,
    /// and sharing the local table could expose master-only fog and controls.
    var supportsInlineThreeDTable: Bool {
        self != .externalPlayer
    }
}

struct GameRootViewer: View {
    let root: GameRoot
    let playerController: PlayerController
    let emptyTitle: LocalizedStringKey
    let contentType: GameMapContentType
    let gameScreenModel: GameScreenModel?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
#if os(iOS) || os(macOS)
    @Environment(AppSettingsModel.self) private var appSettingsModel
#endif
    init(
        root: GameRoot,
        playerController: PlayerController,
        emptyTitle: LocalizedStringKey,
        contentType: GameMapContentType,
        gameScreenModel: GameScreenModel? = nil
    ) {
        self.root = root
        self.playerController = playerController
        self.emptyTitle = emptyTitle
        self.contentType = contentType
        self.gameScreenModel = gameScreenModel
    }

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        GameContentLayer {
            if let mapId = root.mapRoot.gameControllable.gameModel.currentItemId {
                mapView(for: mapId)
            } else {
                GameSetupBackdrop()
            }
        } presentation: {
            if root.mapRoot.gameControllable.gameModel.currentItemId == nil {
                otherViews {
                    EmptyGameContent(
                        title: emptyTitle,
                        startTime: root.gameModel.startGameTime,
                        showsElapsedTime: contentType == .master,
                        // An external/mirrored display is a shared, public
                        // screen (e.g. a second monitor for the whole table) —
                        // never reveal a private join code there.
                        joinCode: contentType == .externalPlayer ? nil : root.ownJoinCode(isMaster: contentType == .master)
                    )
                }
            } else if visibleUpdateType != .map {
                ZStack {
                    GameSetupBackdrop()
                    otherViews { EmptyView() }
                }
            }
        }
        .themedSurface()
        .moduleTint(.game)
        .ignoresSafeArea()
        .onChange(of: root.mapRoot.gameControllable.gameModel.currentItemId, initial: true) { _, newMapId in
            // Only ever turns this on — several `GameRootViewer` instances
            // (master, player, external mirror) can observe independent
            // `currentItemId`s, and flipping back to false from one instance
            // could otherwise race a moment ago's true from another.
            guard newMapId != nil else { return }
            MasterRPGTips.setGameContentVisible(true)
        }
        .onChange(of: scenePhase) { _, phase in
            // Hosting services can stop while the app is suspended; check them when it returns.
            // See CODE_AUDIT_Join §5.3.
            guard phase == .active, contentType != .externalPlayer else { return }
            root.applicationBecameActive()
        }
    }

    @ViewBuilder
    private func mapView(for mapId: UUID) -> some View {
#if os(iOS) || os(macOS)
        if appSettingsModel.showGameTableVolume,
           contentType.supportsInlineThreeDTable {
            // Deliberately not keyed by `mapId`: the table switches maps itself
            // (`GameTableView`'s `.task(id: currentItemId)`). Rebuilding it per map
            // created the new RealityView while the old one was still live, and
            // handing the shared RealityKit scene between the two left the new
            // map's table black.
            GameTableView(root: root, showsEmbeddedToolbar: false)
        } else {
            twoDimensionalMapView(for: mapId)
                .id(mapId)
        }
#else
        twoDimensionalMapView(for: mapId)
            .id(mapId)
#endif
    }

    @ViewBuilder
    private func twoDimensionalMapView(for mapId: UUID) -> some View {
        switch contentType {
        case .master:
            root.mapRoot.viewController.gameMasterMapView(
                root: root.mapRoot,
                id: mapId,
                trailingViewportReservation: mapTrailingViewportReservation,
                bottomViewportReservation: mapBottomViewportReservation
            )
        case .player:
            root.mapRoot.viewController.gameMapView(
                root: root.mapRoot,
                playerId: root.gameModel.gameConfig.id,
                trailingViewportReservation: mapTrailingViewportReservation,
                bottomViewportReservation: mapBottomViewportReservation
            )
        case .externalPlayer:
            root.mapRoot.viewController.gameMapView(root: root.mapRoot, playerId: root.gameModel.gameConfig.id, external: true)
        }
    }

    private var mapTrailingViewportReservation: CGFloat {
        guard contentType != .externalPlayer else { return 0 }
        return gameScreenModel?.mapTrailingViewportReservation ?? 0
    }

    private var mapBottomViewportReservation: CGFloat {
        guard contentType != .externalPlayer else { return 0 }
        return gameScreenModel?.mapBottomViewportReservation ?? 0
    }

    @MainActor @ViewBuilder
    private func otherViews<Content: View>(@ViewBuilder defaultContentView: () -> Content) -> some View {
        Group {
            switch visibleUpdateType {
                case .pdf:
                    root.pdfRoot.viewController.gamePdfView(root: root.pdfRoot)
                case .photo:
                    root.photoRoot.viewController.gameViewer(
                        root: root.photoRoot,
                        trailingViewportReservation: mapTrailingViewportReservation,
                        bottomViewportReservation: mapBottomViewportReservation,
                        controlsBottomInset: gameScreenModel?.fullScreenControlsBottomClearance ?? 0
                    )
                case .space:
                    // visionOS opens the immersive space directly from the
                    // `.onChange` above instead of rendering anything here —
                    // see that handler's comment.
#if os(visionOS)
                    EmptyView()
#else
                    root.spaceRoot.viewController.gameViewer(root: root.spaceRoot)
#endif
                case .table:
                    root.tableRoot.viewController.gameViewer(root: root.tableRoot)
                    .padding(20)
                    .padding(.top, 32)
                case .weather:
                    root.weatherRoot.viewController.gameViewer(root: root.weatherRoot)
                default:
                    defaultContentView()
            }
        }
        .id(currentViewId)
        .overlay(alignment: .bottom) {
            // A photo or weather the game master showed while the map was on screen, now full
            // screen: back onto the map, or closed.
            if showsMapItemControls {
                MapPhotoFullScreenControls(
                    onShowOnMap: { playerController.requestMapPhotoMode(.popover) },
                    onClose: { playerController.requestMapPhotoMode(.closed) }
                )
                .padding()
                .padding(.trailing, mapTrailingViewportReservation)
                .padding(.bottom, mapBottomViewportReservation)
            }
        }
    }

    /// What this surface shows. A shared display never shows a presentation only the game master
    /// opened (a hidden pin's photo): it stays on the map. See `PlayerControllerModel.sharedUpdateType`.
    private var visibleUpdateType: NetworkModules {
        contentType == .externalPlayer
            ? playerController.gameModel.sharedUpdateType
            : playerController.gameModel.gameUpdateType
    }

    private var showsMapItemControls: Bool {
        let mapPhoto = playerController.gameModel.mapPhoto
        return mapPhoto.mode == .fullScreen
            && mapPhoto.presentation?.module == playerController.gameModel.gameUpdateType
    }
    
    private static let defaultViewId = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    private var currentViewId: UUID {
        switch visibleUpdateType {
            case .pdf:
                return root.pdfRoot.gameControllable.gameModel.currentItemId ?? Self.defaultViewId
            case .photo:
                return root.photoRoot.gameControllable.gameModel.currentItemId ?? Self.defaultViewId
            case .space:
                return root.spaceRoot.gameControllable.gameModel.currentItemId ?? Self.defaultViewId
            case .table:
                return root.tableRoot.gameControllable.gameModel.currentItemId ?? Self.defaultViewId
            case .weather:
                return root.weatherRoot.gameControllable.gameModel.currentItemId ?? Self.defaultViewId
            default:
                return Self.defaultViewId
        }
    }
}

/// Stable full-window parent for the active map/table surface and temporary
/// non-map presentation. Game chrome is installed above this layer by the
/// owning game screen and therefore never participates in map layout.
private struct GameContentLayer<Content: View, Presentation: View>: View {
    let content: Content
    let presentation: Presentation

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder presentation: () -> Presentation
    ) {
        self.content = content()
        self.presentation = presentation()
    }

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        // Keep the map/table alive behind temporary presentations without
        // allowing its intrinsic size to become the game window's size.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                presentation
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
    }
}

private struct EmptyGameContent: View {
    let title: LocalizedStringKey
    let startTime: Date
    let showsElapsedTime: Bool
    let joinCode: String?

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        ZStack(alignment: .center) {
            GameSetupBackdrop()

            VStack {
                Spacer()
                Text(title, bundle: .module)
                if showsElapsedTime {
                    // The display has minute resolution: tick once a minute, anchored to the start so it
                    // changes exactly when the elapsed minutes do. See CODE_AUDIT_26 §7.51.
                    TimelineView(.periodic(from: startTime, by: 60)) { context in
                        Text(
                            elapsedDuration(at: context.date),
                            format: .time(pattern: .hourMinute(padHourToLength: 2))
                        )
                        .monospacedDigit()
                    }
                }
                if let joinCode {
                    Text("Join Code: \(Text(joinCode).speechSpellsOutCharacters())", bundle: .module)
                        .font(.title3)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                Spacer()
            }
            .font(.largeTitle)
            .padding()
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func elapsedDuration(at date: Date) -> Duration {
        let elapsedSeconds = max(0, date.timeIntervalSince(startTime)).rounded(.down)
        return .seconds(elapsedSeconds)
    }
}

#Preview {
    GameRootViewer(
        root: .preview,
        playerController: .preview,
        emptyTitle: "Game is running",
        contentType: .master
    )
    .environment(ScenesManager())
    .environment(AppSettingsModel())
}
