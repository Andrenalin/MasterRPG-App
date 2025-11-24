// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGMaps
import WeatherRPG
import RPGTables
import SpaceRPG
import PhotoRPG
import PdfRPG

struct GameRootViewer<MapContent: View>: View {
    let root: GameRoot
    let playerController: PlayerController
    let emptyTitle: LocalizedStringKey
    let mapContentView: (UUID) -> MapContent

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let mapId = root.mapRoot.gameControllable.gameModel.currentItemId {
                mapContentView(mapId)
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
    }
    
    @MainActor @ViewBuilder
    private func otherViews<Content: View>(@ViewBuilder defaultContentView: () -> Content) -> some View {
        switch playerController.gameModel.gameUpdateType {
            case .pdf:
                root.pdfRoot.viewController.gamePdfView(root: root.pdfRoot)
                    .id(root.pdfRoot.gameControllable.gameModel.currentItemId ?? UUID())
            case .photo:
                root.photoRoot.viewController.gamePhotoView(root: root.photoRoot)
                    .id(root.photoRoot.gameControllable.gameModel.currentItemId ?? UUID())
            case .space:
                root.spaceRoot.viewController.gameSpaceView(root: root.spaceRoot)
                    .id(root.spaceRoot.gameControllable.gameModel.currentItemId ?? UUID())
            case .table:
                root.tableRoot.viewController.gameTableView(root: root.tableRoot)
                    .id(root.tableRoot.gameControllable.gameModel.currentItemId ?? UUID())
            case .weather:
                root.weatherRoot.viewController.gameWeatherView(root: root.weatherRoot)
                    .id(root.weatherRoot.gameControllable.gameModel.currentItemId ?? UUID())
            default:
                defaultContentView()
            }
    }
}

#Preview {
    GameRootViewer(root: .preview, playerController: .preview, emptyTitle: "Hello RPG world") { id in
        Text(id.uuidString)
    }
}
