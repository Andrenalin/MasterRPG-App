// @copyright André Trettin

import SwiftUI

enum InlineQuickButtonType: String {
    case one, two, five, ten
    
    var systemImage: String {
        switch self {
        case .one: "1.circle"
        case .two: "2.circle"
        case .five: "5.circle"
        case .ten: "10.circle"
        }
    }
    
    var label: String {
        self.rawValue.capitalized
    }
    
    var duration: CGFloat {
        switch self {
        case .one: 0.3
        case .two: 0.4
        case .five: 0.5
        case .ten: 0.6
        }
    }
    
    func offset(expanded: Bool, layoutDown: Bool) -> CGSize {
        guard expanded else { return .zero }
        
        return switch self {
        case .one: offset(atIndex: 0, layoutDown: layoutDown)
        case .two: offset(atIndex: 1, layoutDown: layoutDown)
        case .five: offset(atIndex: 2, layoutDown: layoutDown)
        case .ten: offset(atIndex: 3, layoutDown: layoutDown)
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

struct InlineQuickEditView: View, Equatable {
    init(itemId: UUID, preopen: Bool, layoutDown: Bool) {
        self.itemId = itemId
        self.preopen = preopen
        self.layoutDown = layoutDown
        self._isExpanded = State(wrappedValue: preopen)
    }
    
    let itemId: UUID
    let preopen: Bool
    let layoutDown: Bool
    
    @Environment(ItemRootController.self) private var root
    
    @Namespace var glassNamespace
    
    @State private var isExpanded: Bool
        
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
            button(type: .one)
            button(type: .two)
            button(type: .five)
            button(type: .ten)
            
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                Label("Edit", systemImage: "pencil.and.scribble")
                    .labelStyle(.iconOnly)
                    .frame(width: 50, height: 50)
            }
            .borderLessTVBottonStyle()
#if !os(visionOS)
            .glassEffect(.regular.tint(.white.opacity(0.5)).interactive())
            .glassEffectID("menu", in: glassNamespace)
#endif
        }
    }
    
    private func button(type: InlineQuickButtonType) -> some View {
        return Button {
            switch type {
            case .one:
                print("1")
            case .two:
                print("2")
            case .five:
                print("5")
            case .ten:
                print("10")
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

