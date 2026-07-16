// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AttachmentSection: View {
    let logController: LogGameController
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroupTV(isExpanded: $isExpanded) {
            ForEach(logController.attachments) { attachment in
                Text("**\(attachment.id)**: \(attachment.itemId)", bundle: .module)
            }
        } label: {
            Text("Attachments in Shareplay", bundle: .module)
        }
    }
}

#Preview {
    @Previewable @State var isExpanded = true
    AttachmentSection(logController: .preview, isExpanded: $isExpanded)
}
