// @copyright André Trettin

import AndrenalinKit
import SwiftUI

#if os(iOS)
    struct CaptureImagePicker: UIViewControllerRepresentable {
        @Binding var shown: Bool
        let updateImage: @Sendable (AKImage?) async -> Void

        @Environment(\.dismiss) private var dismiss

        func makeUIViewController(context: UIViewControllerRepresentableContext<CaptureImagePicker>) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_: UIImagePickerController, context _: UIViewControllerRepresentableContext<CaptureImagePicker>) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self, shown: $shown, updateImage: updateImage)
        }

        @MainActor
        static var isCameraAvailable: Bool {
            UIImagePickerController.isCameraDeviceAvailable(.rear)
                || UIImagePickerController.isCameraDeviceAvailable(.front)
        }

        class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
            let parent: CaptureImagePicker
            let shown: Binding<Bool>
            let updateImage: @Sendable (AKImage) async -> Void

            init(parent: CaptureImagePicker, shown: Binding<Bool>, updateImage: @Sendable @escaping (AKImage) async -> Void) {
                self.parent = parent
                self.updateImage = updateImage
                self.shown = shown
            }

            func imagePickerController(_: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
                guard let unwrapImage = info[UIImagePickerController.InfoKey.originalImage] as? AKImage else { return }
                Task {
                    await updateImage(unwrapImage)
                }
                parent.dismiss()
                shown.wrappedValue = false
            }

            func imagePickerControllerDidCancel(_: UIImagePickerController) {
                parent.dismiss()
                shown.wrappedValue = false
            }
        }
    }
#endif
