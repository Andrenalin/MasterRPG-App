// @copyright André Trettin

import SwiftUI

public struct SharingControlActions {
    public init(control: (() -> [SharingControlModel])?, update: (([SharingControlModel]) -> Void)?) {
        self.control = control
        self.update = update
    }

    public let control: (() -> [SharingControlModel])?
    public let update: (([SharingControlModel]) -> Void)?
}

public extension EnvironmentValues {
    var sharingControlActions: SharingControlActions {
        get { self[SharingControlActionsKey.self] }
        set { self[SharingControlActionsKey.self] = newValue }
    }
}

public struct SharingControlModel: Identifiable, Equatable, Codable, Sendable {
    public init(id: UUID, name: String, show: Bool) {
        self.id = id
        self.name = name
        self.show = show
    }

    public let id: UUID
    public let name: String
    public var show: Bool
}

public struct ControlSharingView: View {
    public init(alignment: Alignment, action: @escaping () -> Void) {
        self.alignment = alignment
        self.action = action
    }

    let action: () -> Void
    let alignment: Alignment

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.gameModus) private var gamemodus
    @Environment(\.sharingControlActions) private var sharingControlActions

    @State private var sharingSize: CGSize = .init(width: 200, height: 100)
    @State private var showSharingFilter = false

    public var body: some View {
        Button {
            showSharingFilter.toggle()
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .selectedBorderedStype(isSelected: sharingFilterActive)
        .overlay(alignment: alignment) {
            SendControlView(controls: controls)
                .opacity(showSharingFilter ? 1 : 0)
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: {
                    sharingSize = $0
                }
                .frame(width: sharingSize.width, height: sharingSize.height, alignment: .topTrailing)
                .offset(y: sharingSize.height + 8)
        }
    }

    private var sharingFilterActive: Bool {
        controls.contains(where: { $0.wrappedValue.show == false })
    }

    private var controls: Binding<[SharingControlModel]> {
        Binding {
            sharingControlActions.control?() ?? []
        } set: { newValue in
            sharingControlActions.update?(newValue)
        }
    }
}

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
                            Image(systemName: control.show ? "square.and.arrow.up" : "square.slash")
                        }
                        .contentTransition(.symbolEffect(.automatic))
                        //.selectedBorderedStype(isSelected: control.show)
                        
                        Text(control.name)
                    }
                    .rowColorBackground(isSelected: false)
                }
            }
            Text("Selected Players get updates", bundle: .main)
        }
        .rowEditColor(backgroundColor: .black)
    }
}

struct SharingControlActionsKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = SharingControlActions(control: nil, update: nil)
}

#Preview {
    @Previewable @State var controls: [SharingControlModel] = [SharingControlModel(id: UUID(), name: "Mega", show: true)]
    NavigationStack {
        Color.blue
            .toolbar {
                ControlSharingView(alignment: .bottomTrailing) {
                    print("")
                }
                .environment(\.sharingControlActions, SharingControlActions(control: { controls }, update: { updated in controls = updated }))
            }
    }
}
