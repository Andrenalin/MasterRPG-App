// @copyright André Trettin

import SwiftUI

public struct SendControlView: View {
    public init(controls: Binding<[SharingControlModel]>) {
        self._controls = controls
    }

    @Binding var controls: [SharingControlModel]
    @Environment(\.sharingControlActions) private var sharingControlActions

    public var body: some View {
        VStack {
            HStack(spacing: 4) {
                ForEach($controls) { $control in
                    VStack(alignment: .center, spacing: 4) {
                        Button {
                            $control.wrappedValue.show.toggle()
                        } label: {
                            Label {
                                Text(control.show ? "Sharing Enabled" : "Sharing Disabled", bundle: .module)
                            } icon: {
                                Image(systemName: control.show ? "square.and.arrow.up" : "square.slash")
                            }
                            .labelStyle(.iconOnly)
                        }
                        .accessibilityLabel(Text("\(control.name): \(control.show ? String(localized: "Enabled", bundle: .module) : String(localized: "Disabled", bundle: .module))"))
                        .accessibilityHint(Text("Toggle sharing for \(control.name)", bundle: .module))
                        .contentTransition(.symbolEffect(.automatic))

                        Text(control.name)
                    }
                    .rowColorBackground(isSelected: false)
                }
            }
            Text("Selected Players get updates", bundle: .module)
        }
        .rowEditColor(backgroundColor: .black)
    }
}

#Preview("Sharing controls") {
    @Previewable @State var controls = [
        SharingControlModel(id: .fixture1, name: "Alice", show: true),
        SharingControlModel(id: .fixture2, name: "Bob", show: false)
    ]
    SendControlView(controls: $controls)
}
