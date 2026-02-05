/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
SwiftUI view that displays the feedback messages for scanning.
*/

#if os(iOS) && !targetEnvironment(simulator)

import Foundation
import RealityKit
import SwiftUI

struct FeedbackView: View {
    @Bindable var messageList: TimedMessageList

    var body: some View {
        VStack {
            if let activeMessage = messageList.activeMessage {
                Text("\(activeMessage.message)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .environment(\.colorScheme, .dark)
                    .transition(.opacity)
            }
        }
    }
}

#endif
