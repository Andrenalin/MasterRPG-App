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
                HeaderPhoto(itemId: imageId, image: image, degrees: degrees, size: size, topMargin: topMargin)
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
                    .overlay(alignment: .bottom) {
                        overlayHeaderView(for: image)
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
}

private extension AnimatedHeaderMap {
    var imageId: Binding<UUID?> {
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

    func containerSize(from image: AKImage) -> CGSize {
        let imageSize = CGSize(width: imageWidth, height: imageHeight)
        let wf = size.width / imageSize.width
        let wh = (size.height - valueFor(iOS: topMargin, macOS: 0, tvOS: topMargin, visionOS: topMargin)) / imageSize.height
        let f = min(wf, wh)
        let width = max(f * imageSize.width, 64)
        let height = max(f * imageSize.height, 64)
        return CGSize(width: width, height: height)
    }

    var imageWidth: CGFloat {
        ((degrees == 0 || degrees == 180) ? image?.size.width : image?.size.height) ?? 300
    }

    var imageHeight: CGFloat {
        ((degrees == 0 || degrees == 180) ? image?.size.height : image?.size.width) ?? 250
    }

    @ViewBuilder
    func overlayHeaderView(for image: AKImage) -> some View {
        Group {
            if isAnimating {
                TimelineView(.periodic(from: .now, by: 2.0)) { timeline in
                    AnimatedMap(editController: editController, image: image, date: timeline.date, size: containerSize(from: image))
                }
            } else {
                AnimatedMap(editController: editController, image: image, date: constTime, size: containerSize(from: image))
            }
        }
        .frame(width: containerSize(from: image).width, height: containerSize(from: image).height)
        .clipShape(.rect(topLeadingRadius: 12, topTrailingRadius: 12))
        .padding(.top, valueFor(iOS: topMargin, macOS: 0, tvOS: topMargin, visionOS: topMargin))
    }
}

#Preview {
    AnimatedHeaderMap(editController: .preview, size: CGSize(width: 300, height: 300), topMargin: 64, inline: false)
}
