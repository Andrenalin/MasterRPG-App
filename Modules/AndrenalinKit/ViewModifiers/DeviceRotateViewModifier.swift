// @copyright André Trettin

import SwiftUI

public extension View {
    func observeRotate(with model: DeviceRotationModel) -> some View {
        self.modifier(DeviceRotationViewModifier(model: model))
    }
}

@MainActor @Observable
public final class DeviceRotationModel: Sendable {
    public init(orientation: DeviceRotationModel.DeviceOrientation = .portraitUp) {
        self.orientation = orientation
    }
    
    public enum DeviceOrientation {
        case portraitUp
        case portraitDown
        case landscapeLeft
        case landscapeRight
    }

    public var orientation: DeviceOrientation
}

struct DeviceRotationViewModifier: ViewModifier {
    let model: DeviceRotationModel

    func body(content: Content) -> some View {
        content
#if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                let newOrientation = mapDeviceOrientation(orientation: UIDevice.current.orientation)
                guard let newOrientation, newOrientation != model.orientation else { return }
                print("*** Changed Rotation")
                model.orientation = newOrientation
            }
#endif
    }

#if os(iOS)
    private func mapDeviceOrientation(orientation: UIDeviceOrientation) -> DeviceRotationModel.DeviceOrientation? {
        switch orientation {
        case .portraitUpsideDown: .portraitDown
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        case .portrait: .portraitUp
        default: nil
        }
    }
#endif
}
