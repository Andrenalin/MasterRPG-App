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
        GeometryReader { geometry in
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
                    .frame(width: 0.85 * geometry.size.width)
                    .padding(.leading)

                ProConListView(
                    prosTitle: prosTitle,
                    pros: pros,
                    consTitle: consTitle,
                    cons: cons
                )

                Spacer()
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .navigationBarTitle(pageName, displayMode: .inline)
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
