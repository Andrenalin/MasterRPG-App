/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI

/// Green checkmark label used to denote a "Do" example.
struct PositiveLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
        }
    }
}

#Preview("Positive guidance") {
    PositiveLabel("Use even lighting")
        .padding()
}

#endif
