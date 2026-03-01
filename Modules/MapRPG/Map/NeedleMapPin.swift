// @copyright André Trettin

import CoreRPG
import SwiftUI

struct NeedleMapPin: View {
    let entries: MapEntryViewerModel
    let entryId: UUID
    let index: Int
    let map: MapModel
    
    @GestureState private var isDragging = false
    @State private var isDraggingStarts = false
    
    var coordinate: CGPoint {
        let entry = entries.entry(entryId)
        guard index >= 0 && index < entry.coordinates.count else { return .zero }
        return entry.coordinates[index]
    }
    
    var body: some View {
        needleView
    }
    
    var needleView: some View {
        VStack(alignment: .center, spacing: 0) {
            needleHeader
                .frame(width: 44, height: 44)
                .animation(.linear, value: entries.isSelected(index: index))
                .overlay(alignment: .center) {
                    Group {
                        addButton
                            .offset(x: entries.isSelected(index: index) ? 36 : 0, y: entries.isSelected(index: index) ? -36 : 0)
                        removeButton
                            .offset(x: entries.isSelected(index: index) ? -36 : 0, y: entries.isSelected(index: index) ? -36 : 0)
                    }
                    .opacity(entries.isSelected(index: index) ? 1 : 0)
                }
            
            needlePath
                .stroke(Color.black, lineWidth: 1, antialiased: true)
                .fill(Color.gray)
                .frame(width: 4, height: 60)
                .zIndex(1)
            
            needlePinPath
                .stroke(Color.black, lineWidth: 1, antialiased: true)
                .fill(Color.gray)
                .frame(width: 4, height: 60)
        }
        .compositingGroup()
        .shadow(radius: 8)
        .zIndex(entries.isSelected(index: index) ? 100 : 1)
    }
    
    var needleHeader: some View {
#if os(macOS)
        headerBar
#else
        Button {
            guard !isDraggingStarts else { return }
            withAnimation(.bouncy) {
                entries.selectedNeedleIndex = entries.selectedNeedleIndex == index ? nil : index
            }
        } label: {
            headerBar
        }
        .buttonStyle(.borderless)
#endif
    }
    
    var headerBar: some View {
        Circle().fill(.black.opacity(0.4))
            .frame(width: entries.isSelected(index: index) ? 84 : 44, height: entries.isSelected(index: index) ? 84 : 44)
            .opacity(entries.isSelected(index: index) ? 1 : 0)
            .overlay(alignment: .center) {
                needHead
            }
            .zIndex(2)
    }
    
    var addButton: some View {
        Button {
            withAnimation { addPin() }
        } label: {
            Image(systemName: "plus")
                .padding()
                .foregroundStyle(.black)
        }
        .frame(width: 44, height: 44)
        .background {
            Color.green
        }
        .clipShape(.circle)
    }
    
    func addPin() {
        var updatedEntry = entries.entry(entryId)
        let next = index + 1 < updatedEntry.coordinates.count ? index + 1 : 0
        var nextPoint = updatedEntry.coordinates[next]
        if next == 0 {
            nextPoint = nextPoint + CGPoint(x: 50, y: 50)
        } else {
            nextPoint = nextPoint - (nextPoint - updatedEntry.coordinates[index]) / 2
        }
        updatedEntry.coordinates.insert(nextPoint, at: next)
        map[updatedEntry.id] = updatedEntry
    }
    
    var removeButton: some View {
        Button {
            withAnimation(.bouncy) {
                entries.selectedNeedleIndex = nil
                removePin()
            }
        } label: {
            Image(systemName: "trash")
                .padding()
                .foregroundStyle(.black)
        }
        .frame(width: 44, height: 44)
        .background {
            Color.red
        }
        .clipShape(.circle)
    }
    
    func removePin() {
        var updatedEntry = entries.entry(entryId)
        if index >= 0 && index < updatedEntry.coordinates.count {
            updatedEntry.coordinates.remove(at: index)
            map[updatedEntry.id] = updatedEntry
        }
    }
    
    var needHead: some View {
        Circle().fill(.teal)
            .stroke(Color.blue, lineWidth: 2, antialiased: true)
            .frame(width: 44, height: 44)
            .zIndex(2)
#if os(tvOS) || os(macOS)
            .gesture(combinedGesture)
#else
            .simultaneousGesture(dragGesture)
#endif
            .onChange(of: isDragging) {
                guard !isDragging else { return }
                Task {
                    isDraggingStarts = false
                    entries.selectedNeedleCoordinate = nil
                    updateCoordinate()
                }
            }
    }
    
    func updateCoordinate() {
        map[entryId] = entries.entry(entryId)
    }
    
    var combinedGesture: some Gesture {
        let tapGesture = TapGesture().onEnded {
            withAnimation {
                withAnimation(.bouncy) {
                    entries.selectedNeedleIndex = entries.selectedNeedleIndex == index ? nil : index
                }
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
        DragGesture(minimumDistance: 3).updating($isDragging) { value, state, _ in
            Task {
                isDraggingStarts = true
                var position = coordinate
                let x = position.x + (value.location.x - value.startLocation.x)
                let y = position.y + (value.location.y - value.startLocation.y)
                position = CGPoint(x: x, y: y)
                entries.update(coordinate: position, for: entryId, at: index)
                entries.selectedNeedleCoordinate = position
            }
            state = true
        }
    }
#endif
    
    var needlePath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: 4, y: 0))
        p.addLine(to: CGPoint(x: 4, y: 60))
        p.addLine(to: CGPoint(x: 0, y: 60))
        p.closeSubpath()
        return p
    }
    
    var needlePinPath: Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.5, y: 0))
        p.addLine(to: CGPoint(x: 3.5, y: 0))
        p.addLine(to: CGPoint(x: 2, y: 6))
        p.closeSubpath()
        return p
    }
}


enum NeedleMapPinButtonType: String {
    case remove, add
    
    var systemImage: String {
        switch self {
        case .remove:
            return "trash"
        case .add:
            return "plus"
        }
    }
    
    var label: String {
        self.rawValue.capitalized
    }
    
    var duration: CGFloat {
        switch self {
        case .remove:
            return 0.3
        case .add:
            return 0.4
        }
    }
    
    func offset(expanded: Bool, layoutDown: Bool) -> CGSize {
        guard expanded else {
            return .zero
        }
        
        switch self {
        case .remove:
            return offset(atIndex: 0, layoutDown: layoutDown)
        case .add:
            return offset(atIndex: 1, layoutDown: layoutDown)
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



#Preview {
    @Previewable var entries = MapEntryViewerModel(mapId: MapModel.previewId, entries: [.empty(MapModel.previewId)])
    
    VStack {
        ForEach(entries.entries[0].coordinates.indexed(), id: \.index) { (index, point) in
            NeedleMapPin(entries: entries, entryId: MapModel.previewId, index: index, map: MapModel.preview)
                .offset(x: entries.entries[0].coordinates[index].x, y: entries.entries[0].coordinates[index].y)
        }
        Spacer()
    }
}
