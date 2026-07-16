/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI

/// Red x-mark label used to denote a "Don't" example.
struct NegativeLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "xmark.circle")
                .foregroundStyle(.red)
        }
    }
}

#Preview("Negative guidance") {
    NegativeLabel("Avoid reflective surfaces")
        .padding()
}

#endif
