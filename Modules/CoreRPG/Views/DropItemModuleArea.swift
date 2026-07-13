// @copyright André Trettin

import SwiftUI

#Preview {
    DropItemModuleArea(module: .adventure) {
        Label("Drop an adventure here", systemImage: "tray.and.arrow.down")
    } dropAction: { _, _, _ in }
    .padding()
}

public struct DropItemModuleArea<Content: View>: View {
    public init(module: NetworkModules, @ViewBuilder contentView: () -> Content, dropAction: @escaping (_ name: String, _ itenId: UUID, _ entryId: UUID?) -> Void) {
        self.module = module
        self.contentView = contentView()
        self.dropAction = dropAction
    }

    let module: NetworkModules
    let contentView: Content
    let dropAction: (_ name: String, _ itenId: UUID, _ entryId: UUID?) -> Void

    @State private var dropBackgroundColor: Color = .clear
    @State private var dropForegroundColor: Color = .primary

    public var body: some View {
        contentView
            .padding(4)
            .foregroundStyle(dropForegroundColor)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(dropBackgroundColor)
            }
            .dropDestination(for: module, handler: dropAction) { inDropArea in
                dropBackgroundColor = inDropArea ? .accentColor : .clear
                dropForegroundColor = inDropArea ? .white : .primary
            }
    }
}
