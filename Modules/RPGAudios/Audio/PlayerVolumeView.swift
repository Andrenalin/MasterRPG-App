// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct PlayerVolumeView: View {
    let root: AudioRoot
    let alignment: Alignment

    @State private var showVolume: Bool = false
    @State private var sharingSize: CGSize = .init(width: 200, height: 64)

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
            Image(systemName: "volume.3", variableValue: Double(root.audioController.model.volume))
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: root.audioController.model.volume)
                .tint(.teal)
        }
    }

    @ViewBuilder
    func volumeChangeView() -> some View {
        @Bindable var model = root.audioController.model

        VStack {
#if !os(tvOS)
            Slider(value: $model.volume, in: 0.0 ... 1.0)
                .frame(width: 160)
                .tint(.teal)
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
