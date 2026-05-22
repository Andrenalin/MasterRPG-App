// @copyright André Trettin

import CoreRPG
import SwiftUI

struct NeedleMapPin: View {
    let entries: MapEntryViewerModel
    let entryId: UUID
    let index: Int
    let map: MapModel
    let mapEditController: MapEditController

    @Namespace var glassNamespace
    @GestureState private var isDragging = false

    private var isSelected: Bool {
        entries.isSelected(index: index)
    }

    var coordinate: CGPoint {
        let entry = entries.entry(entryId)
        guard index >= 0 && index < entry.coordinates.count else { return .zero }
        return entry.coordinates[index]
    }

    var body: some View {
        needleView
    }

    var actionButtons: some View {
        ZStack {
            button(type: .remove)
                .zIndex(110)
            button(type: .add)
                .zIndex(110)

            Color.clear
                .frame(width: 22, height: 22)
                .allowsHitTesting(false)
#if !os(visionOS)
                .glassEffectID("menu", in: glassNamespace)
#endif
        }
    }

    private func button(type: NeedleMapPinButtonType) -> some View {
        Button {
            switch type {
            case .remove:
                removePin()
            case .add:
                addPin()
            }
        } label: {
            Label(type.label, systemImage: type.systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 50, height: 50)
        }
        .borderLessTVBottonStyle()
        .foregroundStyle(.white)
#if !os(visionOS)
        .applyIf(isSelected) {
            $0.glassEffect(.regular.tint(NetworkModules.map.tint.opacity(0.75)).interactive())
        }
        .glassEffectID(type.label, in: glassNamespace)
#endif
        .offset(type.offset(expanded: isSelected, layoutDown: true))
        .animation(.spring(duration: type.duration * 3, bounce: 0.2), value: isSelected)
        .opacity(isSelected ? 1 : 0)
    }

    var needleView: some View {
        VStack(alignment: .center, spacing: 0) {
            needleHeader
                .frame(width: 44, height: 44)

            Self.needlePath
                .stroke(Color.black, lineWidth: 1, antialiased: true)
                .fill(Color.gray)
                .frame(width: 4, height: 60)
                .zIndex(1)

            Self.needlePinPath
                .stroke(Color.black, lineWidth: 1, antialiased: true)
                .fill(Color.gray)
                .frame(width: 4, height: 60)
        }
        .compositingGroup()
        .shadow(radius: 8)
        .zIndex(isSelected ? 100 : 1)
    }

    var needleHeader: some View {
        headerBar
    }

    var headerBar: some View {
        Circle().fill(.black.opacity(0.4))
            .frame(width: 44, height: 44)
            .scaleEffect(isSelected ? 84.0 / 44.0 : 1.0)
            .animation(.spring(duration: 0.9, bounce: 0.2), value: isSelected)
            .opacity(isSelected ? 1 : 0)
            .overlay(alignment: .center) {
                needHead
                    .overlay {
        #if os(visionOS)
                        actionButtons
        #else
                        GlassEffectContainer {
                            actionButtons
                        }
        #endif
                    }
            }
            .zIndex(2)
    }

    func addPin() {
        withAnimation(.bouncy) {
            mapEditController.addNeedlePoint(at: index, entryId: entryId, entries: entries, map: map)
        }
    }

    func removePin() {
        withAnimation(.bouncy) {
            mapEditController.removeNeedlePoint(at: index, entryId: entryId, entries: entries, map: map)
        }
    }

    var needHead: some View {
        Circle().fill(.teal)
            .stroke(Color.blue, lineWidth: 2, antialiased: true)
            .frame(width: 44, height: 44)
            .zIndex(2)
            .gesture(combinedGesture)
            .onChange(of: isDragging) {
                guard !isDragging else { return }
                entries.selectedNeedleCoordinate = nil
                updateCoordinate()
            }
    }

    func updateCoordinate() {
        mapEditController.updateNeedleCoordinate(entryId: entryId, entries: entries, map: map)
    }

    var combinedGesture: some Gesture {
        let tapGesture = TapGesture().onEnded {
            withAnimation(.bouncy) {
                entries.selectedNeedleIndex = isSelected ? nil : index
            }
        }
#if os(tvOS)
        return tapGesture
#else
        return dragGesture.simultaneously(with: tapGesture)
#endif
    }

#if !os(tvOS)
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                var position = coordinate
                position.x += value.location.x - value.startLocation.x
                position.y += value.location.y - value.startLocation.y
                entries.update(coordinate: position, for: entryId, at: index)
                entries.selectedNeedleCoordinate = position
            }
    }
#endif

    private static let needlePath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: 4, y: 0))
        p.addLine(to: CGPoint(x: 4, y: 60))
        p.addLine(to: CGPoint(x: 0, y: 60))
        p.closeSubpath()
        return p
    }()

    private static let needlePinPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0.5, y: 0))
        p.addLine(to: CGPoint(x: 3.5, y: 0))
        p.addLine(to: CGPoint(x: 2, y: 6))
        p.closeSubpath()
        return p
    }()
}

enum NeedleMapPinButtonType: String {
    case remove, add

    var systemImage: String {
        switch self {
        case .remove: return "trash"
        case .add: return "plus"
        }
    }

    var label: String {
        self.rawValue.capitalized
    }

    var duration: CGFloat {
        switch self {
        case .remove: return 0.3
        case .add: return 0.5
        }
    }

    func offset(expanded: Bool, layoutDown: Bool) -> CGSize {
        guard expanded else { return .zero }
        switch self {
        case .remove: return offset(atIndex: 0, layoutDown: layoutDown)
        case .add: return offset(atIndex: 3, layoutDown: layoutDown)
        }
    }

    private func offset(atIndex index: Int, layoutDown: Bool) -> CGSize {
        let radius: CGFloat = 80
        let startAngleDeg = 45.0
        let step = 90.0 / Double(4 - 1)
        let angleDeg = startAngleDeg + (Double(index) * step)
        let angleRad = angleDeg * .pi / 180
        return CGSize(
            width: cos(angleRad) * radius,
            height: sin(angleRad) * radius * (layoutDown ? -1 : 1)
        )
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(MapRootModel.self) var root
    @Previewable var entries = MapEntryViewerModel(mapId: MapModel.previewId, entries: [MapEntryModel.previewGreatHall])
    let mapEditController = MapEditController(editController: root.editController)

    ZStack(alignment: .topLeading) {
        Rectangle().fill(Color.yellow.gradient)
            .ignoresSafeArea()
        
        ForEach(entries.entries[0].coordinates.indexed(), id: \.index) { (index, point) in
            NeedleMapPin(entries: entries, entryId: entries.entries[0].id, index: index, map: MapModel.preview, mapEditController: mapEditController)
                .offset(x: point.x - 22, y: point.y - 110)
        }
    }
}
