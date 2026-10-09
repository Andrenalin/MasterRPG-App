// @copyright André Trettin

import CoreRPG
import SwiftUI
import UniformTypeIdentifiers

/// Labels and symbols of the importer buttons. The fan geometry lives in CoreRPG's
/// `ImporterFanView`. See CODE_AUDIT_Folder §9.6.
enum ImporterButtonType: String {
    case file, url, scanner

    var systemImage: String {
        switch self {
        case .file:
            return "folder"
        case .url:
            return "link.badge.plus"
        case .scanner:
            return "doc.viewfinder"
        }
    }

    var localizedLabel: String {
        switch self {
        case .file:
            String(localized: "File", bundle: .module)
        case .url:
            String(localized: "URL", bundle: .module)
        case .scanner:
            String(localized: "3D Scanner", bundle: .module)
        }
    }
}

struct InlineImporterView: View, Equatable {
    init(itemId: UUID, preopen: Bool, layoutDown: Bool) {
        self.itemId = itemId
        self.preopen = preopen
        self.layoutDown = layoutDown
    }

    let itemId: UUID
    let preopen: Bool
    let layoutDown: Bool

    var body: some View {
#if os(visionOS)
        InlineImporterContentView(itemId: itemId, preopen: preopen, layoutDown: layoutDown)
#else
        GlassEffectContainer {
            InlineImporterContentView(itemId: itemId, preopen: preopen, layoutDown: layoutDown)
        }
#endif
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        // `preopen`/`layoutDown` must be included: `.equatable()` (see ViewController.swift)
        // uses this to decide whether to skip re-rendering, and both drive the fan (its
        // initial state, re-seeded by `ImporterFanView` on a `preopen` change, and its
        // orientation). See CODE_AUDIT_Space §5.6.
        lhs.itemId == rhs.itemId && lhs.preopen == rhs.preopen && lhs.layoutDown == rhs.layoutDown
    }
}

private struct InlineImporterContentView: View {
    let itemId: UUID
    let preopen: Bool
    let layoutDown: Bool

    @Environment(SpaceRootModel.self) private var root
    @State private var canScan: Bool = false

    @State private var showImporter = false
    @State private var showRemoteUrlImporter = false
    @State private var showScanner = false
    @State private var importErrorMessage: String?
    @State private var replacementConfirmation = FileReplacementConfirmation()
    /// What happens to the item's file once a scan replaces it, asked before the scanner opens.
    @State private var scannerReplacedFile: ReplacedFileDisposal = .delete

    var body: some View {
        ImporterFanView(
            title: String(localized: "Importer", bundle: .module),
            systemImage: "graph.3d",
            module: .space,
            preopen: preopen,
            layoutDown: layoutDown,
            items: fanItems
        )
        .task {
#if os(iOS) && !targetEnvironment(simulator)
            canScan = await ConfigCaptureObject.isSupported()
#endif
        }
#if !os(tvOS)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: root.config.fileTypes) { result in
            // A failed pick is reported, not dropped. See CODE_AUDIT_Folder §9.6.
            switch result {
            case .success(let url):
                Task {
                    await replacementConfirmation.resetFile(url: url, itemId: itemId, editControllable: root.editController)
                }
            case .failure(let error):
                importErrorMessage = error.localizedDescription
            }
        }
        .remoteFileURLImporter(
            isPresented: $showRemoteUrlImporter,
            editControllable: root.editController,
            itemId: itemId,
            replacementConfirmation: replacementConfirmation
        )
#endif
#if os(iOS) && !targetEnvironment(simulator)
        // ObjectCaptureSession needs a true full-screen host to reach `cameraTracking == .normal`;
        // inside a page-sheet (`.sheet`) it can stay stuck showing the system's own initial
        // guidance ("Move iPhone to start") indefinitely, since `CapturePrimaryView` only shows
        // its own capture overlay once tracking normalizes.
        .fullScreenCover(isPresented: $showScanner) {
            // Deliberately NOT wrapped in `ManagedPresentationView`: nothing in the
            // scanner reads `@Environment(\.navigator)` (only plain `@Environment(\.dismiss)`
            // in `CaptureCancelButton`), and `ManagedPresentationView` adds real
            // indirection — a `@LazyState`-deferred `Navigator`, `NavigationPresentationModifiers`
            // (its own nested, initially-inactive `.sheet`/`.fullScreenCover`), plus the
            // themed background — between this cover and `ObjectCaptureView`'s own
            // internal Metal view that Apple's sample (a flat `WindowGroup` root) never
            // has. `ObjectCaptureView`'s `CAMetalLayer` needs a real, immediately-correct
            // frame to size its drawable; it never recovers if the layout pass it first
            // sees is degenerate (matching the persistent "CAMetalLayer ignoring invalid
            // setDrawableSize width=0.000000 height=0.000000" — camera hardware active,
            // frames arriving, nothing rendered). Presenting the plain view removes that
            // extra layer rather than trying to work around it.
            Scanner3DRootView(itemId: itemId) { [replaced = scannerReplacedFile] url in
                await root.editController.resetFile(url: url, itemId: itemId, replaced: replaced)
            }
        }
        .onChange(of: showScanner) { _, isShowing in
            root.isScanning3D = isShowing
        }
#endif
        .importFailureAlert(message: $importErrorMessage)
        .fileReplacementAlert(replacementConfirmation)
    }

    /// Only the importers this device can use: the 3D scanner needs object capture support.
    /// See CODE_AUDIT_Folder §9.6.
    private var fanItems: [ImporterFanItem] {
        var types: [ImporterButtonType] = []
#if !os(tvOS)
        types += [.file, .url]
#endif
        if canScan {
            types.append(.scanner)
        }
        return types.map { type in
            ImporterFanItem(id: type.rawValue, title: type.localizedLabel, systemImage: type.systemImage) {
                show(type)
            }
        }
    }

    private func show(_ type: ImporterButtonType) {
        switch type {
        case .file: showImporter.toggle()
        case .url: showRemoteUrlImporter.toggle()
        case .scanner: openScanner()
        }
    }

    /// Opens the scanner, after asking what happens to the file the item already has. The
    /// scanner hands over its model from inside its own sheets, where this view's alert cannot
    /// be shown, so the question comes first; a cancelled scan replaces and deletes nothing.
    private func openScanner() {
        Task {
            guard let replaced = await replacementConfirmation.disposal(forReplacingFileOf: itemId, editControllable: root.editController) else { return }
            scannerReplacedFile = replaced
            showScanner = true
        }
    }
}

#Preview(traits: .mockData) {
    InlineImporterView(itemId: SpaceModel.previewId, preopen: true, layoutDown: true)
}
