// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

struct ItemFileImporterView: View {
    let root: any ItemRootControllable
    let model: any ItemDataAccessible
    let fileTypes: [UTType]
    let isInitial: Bool
    
    var body: some View {
        Group {
            if isInitial {
                InitialStyleView(root: root, model: model, fileTypes: fileTypes, isInitial: isInitial)
            } else {
                OverlayStyleView(root: root, model: model, fileTypes: fileTypes, isInitial: isInitial)
            }
        }
    }
}

private struct InitialStyleView: View {
    let root: any ItemRootControllable
    let model: any ItemDataAccessible
    let fileTypes: [UTType]
    let isInitial: Bool

    var body: some View {
        HStack {
            FileImporterContentView(root: root, model: model, fileTypes: fileTypes, isInitial: isInitial)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(1)
        .transition(.scale)
    }
}

private struct OverlayStyleView: View {
    let root: any ItemRootControllable
    let model: any ItemDataAccessible
    let fileTypes: [UTType]
    let isInitial: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            FilePathDisplayView(model: model, isInitial: isInitial)
                .zIndex(0)

            // Default spacing instead of a fixed minimum. See CODE_AUDIT_Folder §8.4.
            Spacer()

            FileImporterContentView(root: root, model: model, fileTypes: fileTypes, isInitial: isInitial)
                .zIndex(100)
        }
    }
}

private struct FileImporterContentView: View {
    let root: any ItemRootControllable
    let model: any ItemDataAccessible
    let fileTypes: [UTType]
    let isInitial: Bool

    /// Scaled with Dynamic Type. See CODE_AUDIT_Folder §8.4.
    @ScaledMetric(relativeTo: .body) private var initialPadding: CGFloat = 32

    var body: some View {
        if root.viewControllable.fileImporterViewType == .file {
            FileImporterView(
                editControllable: root.editControllable,
                fileTypes: fileTypes,
                itemId: model.id,
                module: root.configurable.module
            )
            .applyIf(isInitial) {
                $0.padding(initialPadding)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.tint, lineWidth: 2)
                    }
            }
        } else {
            root.viewControllable.fileImporterView(
                for: model.id,
                preopen: isInitial,
                layoutDown: !isInitial
            )
        }
    }
}

private struct FilePathDisplayView: View {
    let model: any ItemDataAccessible
    let isInitial: Bool

    /// Scaled with the callout text it surrounds. See CODE_AUDIT_Folder §8.4.
    @ScaledMetric(relativeTo: .callout) private var labelPadding: CGFloat = 6

    var body: some View {
        if !isInitial {
            HStack {
                Text(displayedFileURL ??
                     String(localized: "No file is set", bundle: .module).localizedString)
                    .font(.callout)
            }
            .padding(labelPadding)
#if !os(visionOS)
            .glassEffectAll(.regular.interactive())
#endif
        }
    }

    private var displayedFileURL: String? {
        guard let url = model.url else { return nil }
        switch model.fileUrl?.location {
        case .url:
            return url.absoluteString
        case .appCloud, .newCloud:
            // Stored relative to the module's cloud folder; a file at its root has a bare
            // leading "/" while a file in a folder reads "Folder/Filename".
            return url.path(percentEncoded: false).trimmingPrefix("/").description
        default:
            return url.path(percentEncoded: false)
        }
    }
}

#Preview("File Importer") {
    ItemFileImporterView(
        root: ItemRootController.fake,
        model: FakeItemModel.empty,
        fileTypes: [],
        isInitial: true
    )
}
