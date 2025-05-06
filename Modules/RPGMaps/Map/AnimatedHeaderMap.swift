// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGPhotos

struct AnimatedHeaderMap: View {
    let editController: EditController
    let size: CGSize
    let topMargin: CGFloat
    let inline: Bool

    private let constTime = Date.now
    
    @Environment(MapRoot.self) private var root
    
    @State private var isAnimating = false

    var body: some View {
        @Bindable var model = editController.model
        
        root.photoRoot.viewController.photoView(for: model.photoId, useGame: false) { image, photoDegrees in
            HeaderPhoto(itemId: imageId, image: image, degrees: 0, size: size, topMargin: topMargin) { containerSize in
                if isAnimating {
                    TimelineView(.periodic(from: .now, by: 2.0)) { timeline in
                        AnimatedMap(editController: editController, date: timeline.date, size: containerSize)
                    }
                } else {
                    AnimatedMap(editController: editController, date: constTime, size: containerSize)
                }
            }
#if os(iOS)
            .toolbar {
                ToolbarItem {
                    if inline == false {
                        MapEditSectionEditor(editController: editController)
                    }
                }
            }
#else
            .overlay(alignment: .topTrailing) {
                MapEditSectionEditor(editController: editController)
                    .padding([.top, .trailing])
            }
#endif
            .overlay(alignment: .bottomTrailing) {
                if inline == false {
                    ImageOverlayButton(icon: "film\(isAnimating ? ".fill" : "")") {
                        withAnimation { isAnimating.toggle() }
                    }
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
                    .padding([.trailing, .bottom])
                }
            }
        }
        .onChange(of: model, initial: true) {
            guard model.entries.count < 2 && isAnimating else { return }
            withAnimation { isAnimating = false }
        }
        .onDisappear {
            isAnimating = false
        }
    }
    
    private var imageId: Binding<UUID?> {
        Binding {
            editController.model.id
        } set: { _ in
            // never set
        }
    }
}

#Preview {
    AnimatedHeaderMap(editController: .preview, size: CGSize(width: 300, height: 300), topMargin: 64, inline: false)
}
