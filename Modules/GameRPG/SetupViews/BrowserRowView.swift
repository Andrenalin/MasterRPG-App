// @copyright André Trettin

import CoreRPG
import SwiftUI

struct BrowserRowView: View {
    let root: GameRootController
    let playerNetworkControllable: any PlayerNetworkControllable
    let model: BrowserDeviceModel

    @Environment(\.browserMode) private var browserMode

    var body: some View {
        Group {
            if isDeactivate {
                EmptyView()
            } else {
                VStack {
                    Button {
                        Task {
                            await root.startGame(to: model, mode: gameType)
                        }
                    } label: {
                        Text(labelText, bundle: .module)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDeactivate)
                }
                .padding()
            }
        }
    }
    
    private var labelText: LocalizedStringKey {
        if isConnected {
            return "Disconnect from: \(model.deviceName)"
        }
        if browserMode == .observer {
            return "Observe: \(model.deviceName)"
        }
        return "Connect to: \(model.deviceName)"
    }

    private var gameType: GameType {
        switch browserMode {
        case .observer:
            return .observer
        case .player:
            return .player
        case .proxy:
            return .proxy
        }
    }
}

private extension BrowserRowView {
    var isConnected: Bool {
        playerNetworkControllable.networkModel.playerConnectionId == model.id
    }

    var isDeactivate: Bool {
        playerNetworkControllable.networkModel.playerConnectionId != nil && playerNetworkControllable.networkModel.playerConnectionId != model.id
    }
}

//struct BrowserRowView_Previews: PreviewProvider {
//    static var previews: some View {
//        BrowserRowView(root: .preview, playerNetworkControllable: PlayerNetworkController(name: "TestPLayer"), model: BrowserDeviceModel(id: UUID(), deviceName: "iPad 10"))
//            .previewLayout(.sizeThatFits)
//    }
//}
