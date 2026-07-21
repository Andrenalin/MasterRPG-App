// @copyright André Trettin

import CoreRPG
import SwiftUI
 
struct LogMessageList: View {
    let logController: LogGameController
    
    @State private var showAttachments = true
    
    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        @Bindable var gameModel = logController.gameModel
        VStack {
            SendControlView(controls: $gameModel.gameControl.controls)
                .padding()
            
            List {
                SharingOptionsSection(features: $gameModel.gameControl.features)
                AttachmentSection(logController: logController, isExpanded: $showAttachments)
                LogRowsSection(logController: logController)
            }
#if os(tvOS)
            .listStyle(.grouped)
#else
            .listStyle(.inset)
#endif
        }
    }
}

extension LogMessageDeliveryState {
    var rowBackground: Color {
        switch self {
        case .notTracked:
            return .blue
        case .missingPlayers:
            return .red.opacity(0.7)
        case .partialPlayers:
            return .yellow
        case .allPlayers:
            return .green
        }
    }
}

#Preview {
    LogMessageList(logController: .preview)
        .environment(\.locale, .init(identifier: "de"))
}
