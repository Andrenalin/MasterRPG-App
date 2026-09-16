// @copyright André Trettin

import CoreRPG
import SwiftUI

struct PlayerVolumeView: View {
    let root: AudioRootModel
    let alignment: Alignment

    @State private var showVolume: Bool = false
    @State private var sharingSize: CGSize = .init(width: 200, height: 64)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        #if os(visionOS)
        VStack(alignment: .trailing) {
            volumeChangeView()

            PlayerVolumeButtonView(root: root, showVolume: $showVolume)
        }
        #else
        PlayerVolumeButtonView(root: root, showVolume: $showVolume)
        .overlay(alignment: alignment) {
            volumeChangeView()
                .offset(y: offsetY)
        }
#endif
    }

    @ViewBuilder
    func volumeChangeView() -> some View {
        @Bindable var model = root.audioController.model

        VStack {
#if !os(tvOS)
            VolumeSlider(volume: $model.volume)
                .frame(width: 160)
                .tint(Color.accentColor)
#endif
        }
        .padding(8)
        .fixedSize()
        .rowEditColor(backgroundColor: .black)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: {
            sharingSize = $0
        }
        .frame(width: sharingSize.width, height: sharingSize.height, alignment: .topTrailing)
        .opacity(showVolume ? 1 : 0)
        .allowsHitTesting(showVolume)
        .accessibilityHidden(!showVolume)
    }

    var offsetY: CGFloat {
        #if os(visionOS)
        -(sharingSize.height + 8)
        #else
        sharingSize.height + 8
        #endif
    }
}

#Preview {
    PlayerVolumeView(root: .preview, alignment: .bottomLeading)
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct PlayerVolumeButtonView: View {
    let root: AudioRootModel
    @Binding var showVolume: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VariableVolumeButton(volume: root.audioController.model.volume) {
            showVolume.toggle()
        }
        .tint(Color.accentColor)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityValue(Text(root.audioController.model.volume, format: .percent))
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }
}
