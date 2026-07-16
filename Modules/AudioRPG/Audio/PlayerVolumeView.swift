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

            volumeButtonView
        }
        #else
        volumeButtonView
        .overlay(alignment: alignment) {
            volumeChangeView()
                .offset(y: offsetY)
        }
#endif
    }

    var volumeButtonView: some View {
        Button {
            showVolume.toggle()
        } label: {
            Label {
                Text("Volume", bundle: .module)
            } icon: {
                Image(systemName: "volume.3", variableValue: Double(root.audioController.model.volume))
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce, value: root.audioController.model.volume)
            }
            .labelStyle(.iconOnly)
            .tint(Color.accentColor)
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityValue(Text(root.audioController.model.volume, format: .percent))
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }

    @ViewBuilder
    func volumeChangeView() -> some View {
        @Bindable var model = root.audioController.model

        VStack {
#if !os(tvOS)
            Slider(value: $model.volume, in: 0.0 ... 1.0) {
                Text("Volume", bundle: .module)
            }
                .frame(width: 160)
                .tint(Color.accentColor)
                .accessibilityValue(Text(model.volume, format: .percent))
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
