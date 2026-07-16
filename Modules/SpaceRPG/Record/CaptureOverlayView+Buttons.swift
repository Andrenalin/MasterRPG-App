/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The buttons for the full-screen overlay UI that control the capture.
*/

#if os(iOS) && !targetEnvironment(simulator)

import CoreRPG
import SwiftUI
import RealityKit
import UniformTypeIdentifiers
import os

extension CaptureOverlayView {
    struct DocumentBrowser: UIViewControllerRepresentable {
        let startingDir: URL

        func makeUIViewController(context: UIViewControllerRepresentableContext<DocumentBrowser>) -> UIDocumentPickerViewController {
            let controller = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item])
            controller.directoryURL = startingDir
            return controller
        }

        func updateUIViewController(
            _ uiViewController: UIDocumentPickerViewController,
            context: UIViewControllerRepresentableContext<DocumentBrowser>) {}
    }

    struct VisualEffectRoundedCorner: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(16.0)
                .font(.subheadline)
                .bold()
                .foregroundStyle(.white)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 15))
                .environment(\.colorScheme, .dark)
                .multilineTextAlignment(.center)
        }
    }

    struct VisualEffectView: UIViewRepresentable {
        var effect: UIVisualEffect?
        func makeUIView(context: UIViewRepresentableContext<Self>) -> UIVisualEffectView { UIVisualEffectView() }
        func updateUIView(_ uiView: UIVisualEffectView, context: UIViewRepresentableContext<Self>) { uiView.effect = effect }
    }
}

#endif
