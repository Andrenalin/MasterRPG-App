// @copyright André Trettin

import SwiftUI

public struct SharingControlActions: Equatable, Sendable {
    /// `id` should be stable across the writer's re-renders (e.g. the owning
    /// root model's `ObjectIdentifier`) so SwiftUI's environment diffing can
    /// skip invalidating readers when the same root writes the same
    /// functional closures again. See CODE_AUDIT §8.8.
    public init(id: EnvironmentActionIdentity = .fresh(), control: (@MainActor @Sendable () -> [SharingControlModel])?, update: (@MainActor @Sendable ([SharingControlModel]) -> Void)?) {
        self.id = id
        self.control = control
        self.update = update
    }

    let id: EnvironmentActionIdentity
    public let control: (@MainActor @Sendable () -> [SharingControlModel])?
    public let update: (@MainActor @Sendable ([SharingControlModel]) -> Void)?

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
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
    public init(alignment: Alignment, embeddedInGlass: Bool = false, action: @escaping () -> Void) {
        self.alignment = alignment
        self.embeddedInGlass = embeddedInGlass
        self.action = action
    }

    let action: () -> Void
    let alignment: Alignment
    let embeddedInGlass: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppGameStateModel.self) private var appGameStateModel
    @Environment(\.sharingControlActions) private var sharingControlActions

    @State private var showSharingFilter = false

    public var body: some View {
        Button {
            showSharingFilter.toggle()
        } label: {
            Label {
                Text("Share", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
            .labelStyle(.iconOnly)
        }
        .accessibilityLabel(Text("Sharing Controls", bundle: .module))
        .accessibilityHint(Text("Toggle sharing filter options", bundle: .module))
        .modifier(
            SharingControlButtonStyle(
                embeddedInGlass: embeddedInGlass,
                isActive: sharingFilterActive
            )
        )
        .modifier(
            SharingControlPresentation(
                alignment: alignment,
                usesPopover: embeddedInGlass,
                controls: controls,
                isPresented: $showSharingFilter
            )
        )
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

private struct SharingControlPresentation: ViewModifier {
    let alignment: Alignment
    let usesPopover: Bool
    let controls: Binding<[SharingControlModel]>
    @Binding var isPresented: Bool

    @State private var sharingSize: CGSize = .init(width: 200, height: 100)

    func body(content: Content) -> some View {
#if os(tvOS)
        content
            .overlay(alignment: alignment) {
                SendControlView(controls: controls)
                    .opacity(isPresented ? 1 : 0)
                    .allowsHitTesting(isPresented)
                    .accessibilityHidden(!isPresented)
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self) { proxy in
                        proxy.size
                    } action: {
                        sharingSize = $0
                    }
                    .frame(width: sharingSize.width, height: sharingSize.height, alignment: .topTrailing)
                    .offset(y: sharingSize.height + 8)
            }
#else
        if usesPopover {
            content
                .popover(isPresented: $isPresented) {
                    SendControlView(controls: controls)
                        .padding()
#if os(iOS)
                        .presentationCompactAdaptation(.popover)
#endif
                }
        } else {
            content
                .overlay(alignment: alignment) {
                    SendControlView(controls: controls)
                        .opacity(isPresented ? 1 : 0)
                        .allowsHitTesting(isPresented)
                        .accessibilityHidden(!isPresented)
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
#endif
    }
}

private struct SharingControlButtonStyle: ViewModifier {
    let embeddedInGlass: Bool
    let isActive: Bool

    func body(content: Content) -> some View {
        if embeddedInGlass {
            content
                .buttonStyle(.plain)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        } else {
            content.selectedBorderedStype(isSelected: isActive)
        }
    }
}

struct SharingControlActionsKey: EnvironmentKey {
    static let defaultValue = SharingControlActions(control: nil, update: nil)
}

#Preview {
    @Previewable @State var controls: [SharingControlModel] = [SharingControlModel(id: .fixture1, name: "Mega", show: true)]
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
