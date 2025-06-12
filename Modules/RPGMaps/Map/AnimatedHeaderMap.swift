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
    @State private var image: AKImage?
    @State private var degrees: Double = 0

    var body: some View {
        @Bindable var model = editController.model
        
        Group {
            if let image {
                HeaderPhoto(itemId: imageId, image: image, degrees: 0, size: size, topMargin: topMargin) { containerSize in
                    if isAnimating {
                        TimelineView(.periodic(from: .now, by: 2.0)) { timeline in
                            AnimatedMap(editController: editController, image: image, date: timeline.date, size: containerSize)
                        }
                    } else {
                        AnimatedMap(editController: editController, image: image, date: constTime, size: containerSize)
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
            } else {
                Color.clear
                    .frame(width: size.width, height: size.height)
            }
        }
        .onChange(of: model.id, initial: true) {
            Task {
                await reloadImage()
            }
        }
        .onChange(of: model.entries) {
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

    func reloadImage() async {
        let (updateImage, updateDegrees) = await root.photoRoot.fetchPhotoImage(for: editController.model.photoId, useGame: false) ?? (nil, 0)
        Task { @MainActor in
            self.image = updateImage
            self.degrees <=> updateDegrees
        }
    }
}

#Preview {
    AnimatedHeaderMap(editController: .preview, size: CGSize(width: 300, height: 300), topMargin: 64, inline: false)
}
