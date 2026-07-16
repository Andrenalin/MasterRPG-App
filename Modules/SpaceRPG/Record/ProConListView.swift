/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI

struct ProConListView: View {
    let prosTitle: String
    let pros: [String]
    let consTitle: String
    let cons: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider()
                .padding(.bottom, 5)

            HStack {
                Text(prosTitle)
                    .bold()

                Spacer()

                Text(Image(systemName: "checkmark.circle"))
                    .bold()
                    .foregroundStyle(.green)
            }

            ForEach(pros, id: \.self) { pro in
                Text(pro)
                    .foregroundStyle(.secondary)
            }

            Text(verbatim: " ")
                .hidden()

            Divider()
                .padding(.bottom, 5)

            HStack {
                Text(consTitle)
                    .bold()

                Spacer()

                Text(Image(systemName: "xmark.circle"))
                    .bold()
                    .foregroundStyle(.red)
            }

            ForEach(cons, id: \.self) { con in
                Text(con)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Pros and cons") {
    ProConListView(
        prosTitle: "Best results",
        pros: ["Matte finish", "Even lighting"],
        consTitle: "Avoid",
        cons: ["Reflective surfaces"]
    )
    .padding()
}

#endif
