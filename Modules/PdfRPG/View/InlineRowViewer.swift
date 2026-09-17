// @copyright André Trettin

import CoreRPG
import SwiftUI

struct InlineRowViewer: View, Equatable {
    private static let cornerRadius: CGFloat = 24

    let source: ItemRowModel
    let destination: ItemRowModel
    /// Pre-resolved by the caller where available — see `ViewControllable`'s
    /// doc comment / CODE_AUDIT_10 §8.1. Falls back to `itemOrEmpty` when
    /// nil, so this stays correct for any call site not yet updated.
    var sourceModel: (any ModelType)? = nil

    @Environment(PdfRootModel.self) private var root

    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.navigator) private var navigator


    var body: some View {
        if let cacheController = root.cacheController {
            HStack {
                if source.entryId == nil {
                    ThumbnailRowPhotoView(cacheController: cacheController, model: model, listDisplayModel: root.folderListController.listDisplayModel, entryId: source.entryId)
                        .containerShape(.rect(cornerRadius: Self.cornerRadius))
                        .background {
                            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                                .fill(Color.accentColor.tertiary)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                                .stroke(Color.accentColor.secondary, lineWidth: 2)
                        }
                        .padding(1)
                        .frame(maxWidth: .infinity)
                }
                Button {
                    actionHandler()
                } label: {
                    Label {
                        Text(title)
                    } icon: {
                        Image(systemName: root.configurable.module.icon)
                    }
                }
                .selectedRoundButton(title: title, module: .pdf, isSelected: isPresented)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    var model: PdfModel {
        (sourceModel as? PdfModel) ?? root.itemController.itemOrEmpty(for: source.itemId)
    }

    var title: String {
        String(localized: "Open PDF", bundle: .module)
    }

    var isPresented: Bool {
        scenesManager.getSceneState(for: SceneId(rawValue: root.configurable.module.viewerWindowId)) == .opened
    }

    // Also compares the resolved model's content, not just routing identity — otherwise
    // `.equatable()` (see ViewController.rowViewer) short-circuits `body` even after the
    // referenced PDF is renamed/re-thumbnailed elsewhere, leaving this row stale
    // indefinitely. See CODE_AUDIT_Pdf §8.1.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source && lhs.model.isSame(rhs.model)
    }
    
    private func actionHandler() {
#if os(visionOS) || os(macOS)
        scenesManager.openWindow(SceneId(rawValue: root.configurable.module.viewerWindowId), selection: WindowItemSelection(itemId: destination.itemId, entryId: destination.entryId))
#else
        navigator.navigate(to: DetailRoute.viewer(destination.itemId, destination.entryId), method: .managedSheet)
#endif
    }
}

#Preview(traits: .mockData) {
    InlineRowViewer(source: ItemRowModel(itemId: MockData.previewId, typeId: .pdf), destination: ItemRowModel(itemId: UUID(), entryId: nil, typeId: .table))
}
