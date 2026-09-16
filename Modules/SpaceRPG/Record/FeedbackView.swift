/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
SwiftUI view that displays the feedback messages for scanning.
*/

#if os(iOS) && !targetEnvironment(simulator)

import Foundation
import RealityKit
import SwiftUI

struct FeedbackView: View, Equatable {
    @Bindable var messageList: TimedMessageList

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.messageList === rhs.messageList
    }

    var body: some View {
        VStack {
            if let activeMessage = messageList.activeMessage {
                Text(verbatim: activeMessage.message)
                    .font(.headline)
                    .bold()
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, .dark)
                    .transition(.opacity)
            }
        }
    }
}

#Preview {
    @Previewable var messageList = TimedMessageList()
    FeedbackView(messageList: messageList)
        .task {
            messageList.add("Move slowly around the object")
        }
}

#endif
