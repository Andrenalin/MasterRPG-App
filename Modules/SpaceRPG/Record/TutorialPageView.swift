/*
See the LICENSE.txt file for this sample’s licensing information.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI

struct TutorialPageView: View {
    let pageName: String
    let imageName: String
    let imageCaption: String
    let prosTitle: String
    let pros: [String]
    let consTitle: String
    let cons: [String]

    var body: some View {
        VStack(alignment: .leading) {
            Text(pageName)
                .foregroundStyle(.primary)
                .font(.largeTitle)
                .bold()

            Text(imageCaption)
                .foregroundStyle(.secondary)

            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.85 }
                .padding(.leading)

            ProConListView(
                prosTitle: prosTitle,
                pros: pros,
                consTitle: consTitle,
                cons: cons
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .navigationTitle(pageName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Tutorial page") {
    TutorialPageView(
        pageName: "Capturing Objects",
        imageName: "ObjectCharacteristicsTips",
        imageCaption: "Capture every side of the object in even lighting.",
        prosTitle: "Best results",
        pros: ["Matte finish", "Varied texture"],
        consTitle: "Avoid",
        cons: ["Reflective surfaces"]
    )
}

#endif
