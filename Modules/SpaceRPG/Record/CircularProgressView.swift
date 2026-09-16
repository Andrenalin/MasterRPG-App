/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI

struct CircularProgressView: View, Equatable {
    var body: some View {
        VStack {
            Spacer()
            ZStack {
                Spacer()
                ProgressView()
                    .progressViewStyle(
                        CircularProgressViewStyle(tint: .primary)
                    )
                Spacer()
            }
            Spacer()
        }
    }
}

#Preview {
    CircularProgressView()
}

#endif
