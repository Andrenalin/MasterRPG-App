/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The view that plays the tutorial.
*/

#if os(iOS) && !targetEnvironment(simulator)

import SwiftUI

struct TutorialVideoView: View {
    @Environment(AppDataModel.self) private var appModel
    let url: URL
    let isInReviewSheet: Bool
    @State private var isShowing = false

    private let textDelay: TimeInterval = 0.3
    private let animationDuration: TimeInterval = 4
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            PlayerView(
                url: url,
                isTransparent: true,
                isStacked: false,
                isInverted: isInReviewSheet && colorScheme == .light,
                shouldLoop: false
            )
            .opacity(isShowing ? 1 : 0)
            .accessibilityLabel(Text("Scanning tutorial", bundle: .module))
            .overlay(alignment: .bottom) {
                if !isInReviewSheet {
                    Text(appModel.orbit.feedbackString(isObjectFlippable: appModel.isObjectFlippable))
                        .font(.headline)
                        .opacity(isShowing ? 1 : 0)
                        .padding(.bottom, 16)
                }
            }
            if isInReviewSheet {
                Spacer(minLength: 28)
            }
        }
        .foregroundStyle(.white)
        .task {
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(textDelay))
                guard !Task.isCancelled else { return }
            }
            withAnimation(reduceMotion ? nil : .default) {
                isShowing = true
            }
        }
        .task {
            guard !isInReviewSheet else { return }
            try? await Task.sleep(for: .seconds(animationDuration))
            guard !Task.isCancelled else { return }
            appModel.orbitState = .capturing
        }
    }
}

#Preview {
    TutorialVideoView(
        url: URL(filePath: "/dev/null"),
        isInReviewSheet: true
    )
    .environment(AppDataModel.instance)
}

#endif
