/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Custom SwiftUI View for showing the tutorial stack.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI

/// Top-level view containing a tabbed view of each of the help pages.
struct HelpPageView: View {
    @Binding var showInfo: Bool

    var body: some View {
        ZStack {
            VStack(alignment: .leading) {
                HStack {
                    Text("Capture Help", bundle: .module).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: {
                        withAnimation {
                            showInfo = false
                        }},
                           label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.init(white: 0.7, opacity: 0.5))
                            .font(.title)
                    })
                }

                TabView {
                    ObjectHelpPageView()
                    EnvironmentHelpPageView()
                }
                .tabViewStyle(PageTabViewStyle())
                .onAppear() {
                    UIPageControl.appearance().currentPageIndicatorTintColor = .black
                    UIPageControl.appearance().pageIndicatorTintColor = .lightGray
                }

            }.padding()
        }
        .navigationTitle(Text("Scanning Info", bundle: .module))
    }
}

#Preview {
    ObjectHelpPageView()
}

#Preview {
    EnvironmentHelpPageView()
}

#Preview("Help") {
    HelpPagePreview()
}

private struct HelpPagePreview: View {
    @State private var showInfo = true

    var body: some View {
        NavigationStack {
            HelpPageView(showInfo: $showInfo)
        }
    }
}

private struct TutorialPageView: View {
    let pageName: String
    let imageName: String
    let imageCaption: String
    let prosTitle: String
    let pros: [String]
    let consTitle: String
    let cons: [String]

    var body: some View {
        GeometryReader { geomReader in
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
                // Leaves 25% margins.
                    .frame(width: 0.85 * geomReader.size.width)
                    .padding(.leading)

                ProConListView(prosTitle: prosTitle, pros: pros, consTitle: consTitle, cons: cons)

                Spacer()
            }
            .frame(width: geomReader.size.width, height: geomReader.size.height)
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

private struct ObjectHelpPageView: View {
    var body: some View {
        let caption = "Opaque, matte objects with varied surface textures scan best. Capture all sides of your object in a series of orbits.\n"

        TutorialPageView(pageName: "Capturing Objects",
                         imageName: "ObjectCharacteristicsTips",
                         imageCaption: caption,
                         prosTitle: "Ideal Object Characteristics",
                         pros: ["Varied Surface Texture",
                                "Non-reflective, matte surface",
                                "Solid, opaque" ],
                         consTitle: "May Reduce Quality",
                         cons: ["Shiny materials",
                                "Transparent, transluscent objects"])
    }
}

private struct EnvironmentHelpPageView: View {
    var body: some View {
        let caption = "Make sure you have even, good lighting and a stable environment for scanning.  If scanning outdoors, cloudy days work best.\n"
        TutorialPageView(pageName: "Environment",
                         imageName: "EnvironmentTips",
                         imageCaption: caption,
                         prosTitle: "Ideal Environment Characteristics",
                         pros: ["Diffuse, consistent lighting",
                                "Space around intended object",
                                " "],
                         consTitle: "May Reduce Quality",
                         cons: ["Sunny, directional lighting",
                                "Inconsistent shadows"])
    }
}

private struct ProConListView: View {
    let prosTitle: String
    let pros: [String]
    let consTitle: String
    let cons: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider()
                .padding(.bottom, 5.0)

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

            Text("HIDDEN SPACER")
                .hidden()

            Divider()
                .padding(.bottom, 5.0)

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

/// Green checkmark label used to denote a "Do" example.
private struct PositiveLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Group {
            Label(title: {
                Text(text)
                    .foregroundStyle(.secondary)
            }, icon: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
            })
        }
    }
}

#Preview("Positive guidance") {
    PositiveLabel("Use even lighting")
        .padding()
}

/// Red x-mark label used to denote a "Don't" example.
private struct NegativeLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Group {
            Label(title: {
                Text(text)
                    .foregroundStyle(.secondary)
            }, icon: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.red)
            })
        }
    }
}

#Preview("Negative guidance") {
    NegativeLabel("Avoid reflective surfaces")
        .padding()
}

#endif
