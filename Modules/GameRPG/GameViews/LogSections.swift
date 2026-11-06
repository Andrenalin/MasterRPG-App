// @copyright André Trettin

import SwiftUI

/// The sections of the Logs window: the sharing options, the SharePlay attachments and the
/// messages. The Logs window and the game master's Players panel show the same three.
struct LogSections: View {
    let logController: LogGameController

    @State private var showAttachments = true

    var body: some View {
        @Bindable var gameModel = logController.gameModel
        SharingOptionsSection(features: $gameModel.gameControl.features)
        AttachmentSection(logController: logController, isExpanded: $showAttachments)
        LogRowsSection(logController: logController)
    }
}
