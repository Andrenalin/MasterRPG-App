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
                            .foregroundStyle(Color(white: 0.7, opacity: 0.5))
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
                    UIPageControl.appearance().currentPageIndicatorTintColor = .black
                    UIPageControl.appearance().pageIndicatorTintColor = .lightGray
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
