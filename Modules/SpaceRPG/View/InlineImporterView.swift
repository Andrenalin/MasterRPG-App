// @copyright André Trettin

import CoreRPG
import SwiftUI
import UniformTypeIdentifiers

enum ImporterButtonType: String {
    case file, scanner
    
    var systemImage: String {
        switch self {
        case .file:
            return "folder"
        case .scanner:
            return "doc.viewfinder"
        }
    }
    
    var label: String {
        self.rawValue.capitalized
    }
    
    var duration: CGFloat {
        switch self {
        case .file:
            return 0.5
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
            return offset(atIndex: 2, layoutDown: layoutDown)
        case .scanner:
            return offset(atIndex: 3, layoutDown: layoutDown)
        }
    }
    
    private func offset(atIndex index: Int, layoutDown: Bool) -> CGSize {
        let radius: CGFloat = 120
        let startAngleDeg = -180.0
        let step = 90.0 / Double(4 - 1)
        
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
    @State private var canScan: Bool = false
    
    @Namespace var glassNamespace
    
    @State private var isExpanded: Bool
    
    @State private var showImporter = false
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
            button(type: .scanner)
            
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                Label("Importer", systemImage: "graph.3d")
                    .labelStyle(.iconOnly)
                    .frame(width: 50, height: 50)
            }
            .borderLessTVBottonStyle()
#if !os(visionOS)
            .glassEffect(.regular.tint(.white.opacity(0.5)).interactive())
            .glassEffectID("menu", in: glassNamespace)
#endif
        }
        .task {
#if os(iOS) && !targetEnvironment(simulator)
            canScan = await ConfigCaptureObject.isSupported()
#endif
        }
#if !os(tvOS)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: root.config.fileTypes) { result in
            guard let url = try? result.get() else { return }
            root.editController.resetSpace(url: url)
        }
#endif
#if os(iOS)
        .sheet(isPresented: $showScanner) {
            Scanner3DRootView()
        }
#endif
    }
    
    private func button(type: ImporterButtonType) -> some View {
        return Button {
            switch type {
            case .file:
                showImporter.toggle()
            case .scanner:
                showScanner.toggle()
            }
        } label: {
            Label(type.label, systemImage: type.systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 50, height: 50)
                .opacity(isExpanded ? 1 : 0)
        }
        .borderLessTVBottonStyle()
#if !os(visionOS)
        .glassEffect(.regular.tint(.white.opacity(0.5)).interactive())
        .glassEffectID(type.label, in: glassNamespace)
#endif
        .offset(type.offset(expanded: isExpanded, layoutDown: layoutDown))
        .animation(.spring(duration: type.duration * 3, bounce: 0.2), value: isExpanded)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemId == rhs.itemId
    }
}
