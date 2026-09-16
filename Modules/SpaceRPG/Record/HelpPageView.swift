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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            VStack(alignment: .leading) {
                HStack {
                    Text("Capture Help", bundle: .module)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        withAnimation(reduceMotion ? nil : .default) {
                            showInfo = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title)
                    }
                    .accessibilityLabel(Text("Close", bundle: .module))
                }

                TabView {
                    ObjectHelpPageView()
                    EnvironmentHelpPageView()
                }
                .tabViewStyle(.page)
                .onAppear {
                    // `.label`/`.tertiaryLabel` are dynamic UIColors that resolve themselves
                    // per current trait collection, unlike the fixed `.black`/`.lightGray` this
                    // replaced (invisible in dark mode). See CODE_AUDIT_Space §8.6.
                    UIPageControl.appearance().currentPageIndicatorTintColor = .label
                    UIPageControl.appearance().pageIndicatorTintColor = .tertiaryLabel
                }
            }
            .padding()
        }
        .navigationTitle(Text("Scanning Info", bundle: .module))
    }
}

#Preview("Help") {
    @Previewable @State var showInfo = true

    NavigationStack {
        HelpPageView(showInfo: $showInfo)
    }
}

#endif
