/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI

struct CircularProgressView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack {
            Spacer()
            ZStack {
                Spacer()
                ProgressView()
                    .progressViewStyle(
                        CircularProgressViewStyle(tint: colorScheme == .light ? .black : .white)
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
