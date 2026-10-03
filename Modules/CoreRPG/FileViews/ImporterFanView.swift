// @copyright André Trettin

import SwiftUI

/// One way to import a file into an item, shown as a button of an `ImporterFanView`.
public struct ImporterFanItem: Identifiable {
    public init(id: String, title: String, systemImage: String, action: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public let id: String
    public let title: String
    public let systemImage: String
    public let action: @MainActor () -> Void
}

/// A round importer button that fans out the import options above (or below) it.
///
/// Photo and Space each carried a copy of this fan, and the copies drifted apart: Photo tinted
/// its button with the Space colour and lacked the `preopen` reset, both showed buttons the
/// device cannot use. Callers pass only the items the device supports. The view re-seeds
/// `isExpanded` from `preopen` whenever `preopen` changes. See CODE_AUDIT_Folder §9.6.
public struct ImporterFanView: View {
    public init(
        title: String,
        systemImage: String,
        module: NetworkModules,
        preopen: Bool,
        layoutDown: Bool,
        items: [ImporterFanItem]
    ) {
        self.title = title
        self.systemImage = systemImage
        self.module = module
        self.preopen = preopen
        self.layoutDown = layoutDown
        self.items = items
    }

    let title: String
    let systemImage: String
    let module: NetworkModules
    let preopen: Bool
    let layoutDown: Bool
    let items: [ImporterFanItem]

    public var body: some View {
        // `@State` takes its initial value only once per view identity, so a new `preopen`
        // needs a new identity to re-seed `isExpanded`.
        ImporterFanContent(
            title: title,
            systemImage: systemImage,
            module: module,
            preopen: preopen,
            layoutDown: layoutDown,
            items: items
        )
        .id(preopen)
    }
}

private struct ImporterFanContent: View {
    init(title: String, systemImage: String, module: NetworkModules, preopen: Bool, layoutDown: Bool, items: [ImporterFanItem]) {
        self.title = title
        self.systemImage = systemImage
        self.module = module
        self.layoutDown = layoutDown
        self.items = items
        self._isExpanded = State(wrappedValue: preopen)
    }

    let title: String
    let systemImage: String
    let module: NetworkModules
    let layoutDown: Bool
    let items: [ImporterFanItem]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded: Bool

    var body: some View {
        ZStack {
            ForEach(items.enumerated(), id: \.element.id) { index, item in
                ImporterFanButton(
                    item: item,
                    module: module,
                    isExpanded: isExpanded,
                    offset: ImporterFanLayout.offset(index: index, count: items.count, expanded: isExpanded, layoutDown: layoutDown),
                    duration: ImporterFanLayout.duration(index: index)
                )
            }

            Button {
                withAnimation(reduceMotion ? nil : .default) {
                    isExpanded.toggle()
                }
            } label: {
                Label { Text(title) } icon: { Image(systemName: systemImage) }
                    .frame(width: ImporterFanLayout.buttonSize, height: ImporterFanLayout.buttonSize)
            }
            .selectedRoundButton(title: title, module: module, isSelected: isExpanded)
        }
    }
}

private struct ImporterFanButton: View {
    let item: ImporterFanItem
    let module: NetworkModules
    let isExpanded: Bool
    let offset: CGSize
    let duration: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: item.action) {
            Label {
                Text(item.title)
            } icon: {
                Image(systemName: item.systemImage)
            }
            .frame(width: ImporterFanLayout.buttonSize, height: ImporterFanLayout.buttonSize)
            .opacity(isExpanded ? 1 : 0)
        }
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
        .selectedRoundButton(title: item.title, module: module, isSelected: false)
        .offset(offset)
        .animation(
            reduceMotion ? nil : .spring(duration: duration * 3, bounce: 0.2),
            value: isExpanded
        )
    }
}

/// The fan's geometry: the buttons spread over a quarter circle to the left of the toggle.
enum ImporterFanLayout {
    static let buttonSize: CGFloat = 32
    static let radius: CGFloat = 120

    static func offset(index: Int, count: Int, expanded: Bool, layoutDown: Bool) -> CGSize {
        guard expanded else { return .zero }
        let step = count > 1 ? 90.0 / Double(count - 1) : 0
        let angle = (-180.0 + Double(index) * step) * .pi / 180
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius * (layoutDown ? -1 : 1))
    }

    /// Later buttons arrive a little later.
    static func duration(index: Int) -> CGFloat {
        0.3 + CGFloat(index) * 0.075
    }
}

public extension View {
    /// The alert an importer shows when picking or loading a file failed, instead of the
    /// failure looking like nothing happened. See CODE_AUDIT_Folder §9.6.
    func importFailureAlert(message: Binding<String?>) -> some View {
        alert(
            Text("Import Failed", bundle: .module),
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented { message.wrappedValue = nil }
                }
            )
        ) {
            Button(role: .cancel) {
                message.wrappedValue = nil
            } label: {
                Text("OK", bundle: .module)
            }
        } message: {
            Text(verbatim: message.wrappedValue ?? "")
        }
    }
}
