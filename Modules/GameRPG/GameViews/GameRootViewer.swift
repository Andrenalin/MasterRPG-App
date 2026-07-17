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
}

struct GameRootViewer: View {
    let root: GameRoot
    let playerController: PlayerController
    let emptyTitle: LocalizedStringKey
    let contentType: GameMapContentType

    @Environment(\.colorScheme) private var colorScheme
    @Environment(ScenesManager.self) private var scenesManager

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        Group {
            if let mapId = root.mapRoot.gameControllable.gameModel.currentItemId {
                mapView(for: mapId)
                    .id(mapId)
                    .overlay {
                        if playerController.gameModel.gameUpdateType != .map {
                            ZStack {
                                Color.black.opacity(0.80)

                                otherViews { EmptyView() }
                            }
                        }
                    }
            } else {
                otherViews {
                    ZStack(alignment: .center) {
                        MeshAnimationView()
                        
                        VStack {
                            Spacer()
                            Text(emptyTitle, bundle: .module)
                            Text(root.gameModel.startGameTime, style: .relative)
                            Spacer()
                        }
                        .font(.largeTitle)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
#if os(iOS)
        .background(colorScheme == .dark ? Color.black : Color.white)
#endif
        .ignoresSafeArea()
#if os(visionOS)
        .onChange(of: root.photoRoot.gameControllable.gameModel.currentItemId) {
            guard let photoId = root.photoRoot.gameControllable.gameModel.currentItemId else { return }
            root.photoRoot.imagePresentationModel.selectedItemId = photoId
            scenesManager.openWindow(SceneId.imageSpaceViewer)
        }
#endif
    }
    
    @ViewBuilder
    private func mapView(for mapId: UUID) -> some View {
        switch contentType {
        case .master:
            root.mapRoot.viewController.gameMasterMapView(root: root.mapRoot, id: mapId)
        case .player:
            root.mapRoot.viewController.gameMapView(root: root.mapRoot, playerId: root.gameModel.gameConfig.id)
        case .externalPlayer:
            root.mapRoot.viewController.gameMapView(root: root.mapRoot, playerId: root.gameModel.gameConfig.id, external: true)
        }
    }

    @MainActor @ViewBuilder
    private func otherViews<Content: View>(@ViewBuilder defaultContentView: () -> Content) -> some View {
        Group {
            switch playerController.gameModel.gameUpdateType {
                case .pdf:
                    root.pdfRoot.viewController.gamePdfView(root: root.pdfRoot)
                case .photo:
                    root.photoRoot.viewController.gameViewer(root: root.photoRoot)
                case .space:
                    root.spaceRoot.viewController.gameViewer(root: root.spaceRoot)
                case .table:
                    root.tableRoot.viewController.gameViewer(root: root.tableRoot)
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

#Preview {
    GameRootViewer(root: .preview, playerController: .preview, emptyTitle: "Game is running", contentType: .master)
}
