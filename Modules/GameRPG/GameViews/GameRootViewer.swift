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
    @Environment(ScenesManager.self) private var scenesManager
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
                    .id(mapId)
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
            } else if playerController.gameModel.gameUpdateType != .map {
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
#if os(visionOS)
        .onChange(of: root.photoRoot.gameControllable.gameModel.currentItemId) {
            guard let photoId = root.photoRoot.gameControllable.gameModel.currentItemId else { return }
            root.photoRoot.imagePresentationModel.selectedItemId = photoId
            scenesManager.openWindow(SceneId.imageSpaceViewer)
        }
        // Goes straight to the immersive space instead of routing through the
        // `otherViews` reveal panel (see the `.space` case below): that panel
        // is a full-window 2D overlay meant for bounded content (pdf/photo/
        // table/weather); on visionOS it was hosting only SpaceQuickLook's
        // near-invisible trigger button, which briefly blanked the game
        // window while the real `ImmersiveSpace` opened in the background.
        //
        // Skipped while the volumetric game-table window is open: its own
        // `GameTableView`/`GameTableModel.loadSpaceObject(itemId:spaceRoot:)`
        // renders the shared object directly above the table (same TabletopKit
        // scene/seating), so opening a second, separate immersive space here
        // would just duplicate it.
        .onChange(of: root.spaceRoot.gameControllable.gameModel.currentItemId) {
            guard let spaceId = root.spaceRoot.gameControllable.gameModel.currentItemId else {
                // The GM un-revealed the space entirely — clear any earlier
                // explicit dismiss so a future re-reveal (even of the same
                // item) opens fresh instead of staying permanently suppressed.
                scenesManager.clearExplicitlyDismissedSpaceItem()
                return
            }
            guard scenesManager.getSceneState(for: .gameTable) != .opened else { return }
            // A player who explicitly closed this exact reveal (the space
            // viewer's own close button) shouldn't have it popped back open
            // by a resync that re-broadcasts the same still-revealed item —
            // see `ScenesManager.explicitlyDismissedSpaceItemId`.
            guard scenesManager.explicitlyDismissedSpaceItemId != spaceId else { return }
            Task {
                await scenesManager.openSpaceViewer(selection: ItemSelection(itemId: spaceId, entryId: nil))
            }
        }
#endif
    }

    @ViewBuilder
    private func mapView(for mapId: UUID) -> some View {
#if os(iOS) || os(macOS)
        if appSettingsModel.showGameTableVolume,
           contentType.supportsInlineThreeDTable {
            GameTableView(root: root, retentionModel: gameScreenModel)
        } else {
            twoDimensionalMapView(for: mapId)
        }
#else
        twoDimensionalMapView(for: mapId)
#endif
    }

    @ViewBuilder
    private func twoDimensionalMapView(for mapId: UUID) -> some View {
        switch contentType {
        case .master:
            root.mapRoot.viewController.gameMasterMapView(
                root: root.mapRoot,
                id: mapId,
                trailingViewportReservation: mapTrailingViewportReservation
            )
        case .player:
            root.mapRoot.viewController.gameMapView(
                root: root.mapRoot,
                playerId: root.gameModel.gameConfig.id,
                trailingViewportReservation: mapTrailingViewportReservation
            )
        case .externalPlayer:
            root.mapRoot.viewController.gameMapView(root: root.mapRoot, playerId: root.gameModel.gameConfig.id, external: true)
        }
    }

    private var mapTrailingViewportReservation: CGFloat {
        guard contentType != .externalPlayer else { return 0 }
        return gameScreenModel?.mapTrailingViewportReservation ?? 0
    }

    @MainActor @ViewBuilder
    private func otherViews<Content: View>(@ViewBuilder defaultContentView: () -> Content) -> some View {
        Group {
            switch playerController.gameModel.gameUpdateType {
                case .pdf:
                    root.pdfRoot.viewController.gamePdfView(root: root.pdfRoot)
                case .photo:
                    root.photoRoot.viewController.gameViewer(
                        root: root.photoRoot,
                        trailingViewportReservation: mapTrailingViewportReservation
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
    }
    
    private static let defaultViewId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private var currentViewId: UUID {
        switch playerController.gameModel.gameUpdateType {
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
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(
                            elapsedDuration(at: context.date),
                            format: .time(pattern: .hourMinute(padHourToLength: 2))
                        )
                        .monospacedDigit()
                    }
                }
                if let joinCode {
                    Text("Join Code: \(joinCode)", bundle: .module)
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
