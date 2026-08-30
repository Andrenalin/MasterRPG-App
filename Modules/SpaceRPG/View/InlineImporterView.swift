// @copyright André Trettin

import CoreRPG
import SwiftUI
import UniformTypeIdentifiers

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
    
    var duration: CGFloat {
        switch self {
        case .file:
            return 0.5
        case .url:
            return 0.55
        case .scanner:
            return 0.6
        }
    }
    
    func offset(expanded: Bool, layoutDown: Bool) -> CGSize {
        guard expanded else {
            return .zero
        }
        
        switch self {
        case .file:
            return offset(atIndex: 0, layoutDown: layoutDown)
        case .url:
            return offset(atIndex: 1, layoutDown: layoutDown)
        case .scanner:
            return offset(atIndex: 2, layoutDown: layoutDown)
        }
    }
    
    private func offset(atIndex index: Int, layoutDown: Bool) -> CGSize {
        let radius: CGFloat = 120
        let startAngleDeg = -180.0
        let step = 90.0 / Double(3 - 1)
        
        let angleDeg = startAngleDeg + (Double(index) * step)
        let angleRad = angleDeg * .pi / 180
        
        let x = cos(angleRad) * radius
        let y = sin(angleRad) * radius * (layoutDown ? -1 : 1)
        
        return CGSize(width: x, height: y)
    }
}

struct InlineImporterView: View, Equatable {
    init(itemId: UUID, preopen: Bool, layoutDown: Bool) {
        self.itemId = itemId
        self.preopen = preopen
        self.layoutDown = layoutDown
        self._isExpanded = State(wrappedValue: preopen)
    }
    
    let itemId: UUID
    let preopen: Bool
    let layoutDown: Bool
    
    @Environment(SpaceRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var canScan: Bool = false
    
    @Namespace var glassNamespace
    
    @State private var isExpanded: Bool
    
    @State private var showImporter = false
    @State private var showRemoteURLImporter = false
    @State private var showScanner = false
    
    var body: some View {
#if os(visionOS)
        content
#else
        GlassEffectContainer {
            content
        }
#endif
    }
    
    var content: some View {
        ZStack {
            button(type: .file)
            button(type: .url)
            button(type: .scanner)
            
            Button {
                withAnimation(reduceMotion ? nil : .default) {
                    isExpanded.toggle()
                }
            } label: {
                Label { Text(importerTitle) } icon: { Image(systemName: "graph.3d") }
                    .frame(width: 32, height: 32)
            }
            .selectedRoundButton(title: importerTitle, module: .space, isSelected: isExpanded)
        }
        .task {
#if os(iOS) && !targetEnvironment(simulator)
            canScan = await ConfigCaptureObject.isSupported()
#endif
        }
#if !os(tvOS)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: root.config.fileTypes) { result in
            guard let url = try? result.get() else { return }
            Task {
                await root.editController.resetFile(url: url, itemId: itemId)
            }
        }
        .remoteFileURLImporter(
            isPresented: $showRemoteURLImporter,
            editControllable: root.editController,
            itemId: itemId
        )
#endif
#if os(iOS) && !targetEnvironment(simulator)
        .sheet(isPresented: $showScanner) {
            ManagedPresentationView {
                Scanner3DRootView(itemId: itemId) { url in
                    await root.editController.resetFile(url: url, itemId: itemId)
                }
            }
        }
#endif
    }
    
    private var importerTitle: String {
        String(localized: "Importer", bundle: .module)
    }
    
    private func button(type: ImporterButtonType) -> some View {
        return Button {
            switch type {
            case .file:
                showImporter.toggle()
            case .url:
                showRemoteURLImporter.toggle()
            case .scanner:
                showScanner.toggle()
            }
        } label: {
            Label {
                Text(type.localizedLabel)
            } icon: {
                Image(systemName: type.systemImage)
            }
            .frame(width: 32, height: 32)
            .opacity(isExpanded ? 1 : 0)
        }
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
        .selectedRoundButton(title: type.localizedLabel, module: .space, isSelected: false)
        .offset(type.offset(expanded: isExpanded, layoutDown: layoutDown))
        .animation(
            reduceMotion ? nil : .spring(duration: type.duration * 3, bounce: 0.2),
            value: isExpanded
        )
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        // `preopen`/`layoutDown` must be included: `.equatable()` (see ViewController.swift)
        // uses this to decide whether to skip re-rendering, and both drive stored state
        // (`isExpanded`'s seed, the button-fan's orientation) that must update when they
        // change for the same `itemId`. See CODE_AUDIT_9 §5.1.
        lhs.itemId == rhs.itemId && lhs.preopen == rhs.preopen && lhs.layoutDown == rhs.layoutDown
    }
}

#Preview(traits: .mockData) {
    InlineImporterView(itemId: SpaceModel.previewId, preopen: true, layoutDown: true)
}
