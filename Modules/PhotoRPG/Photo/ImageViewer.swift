// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ImageViewer: View {
    init(id: UUID, image: AKImage, photoDegrees: Double, containerSize: CGSize, contentMode: ContentMode, toolBarModel: GameToolBarModel?) {
        self.id = id
        self.image = image
        self.containerSize = containerSize
        self.contentMode = contentMode
        self.toolBarModel = toolBarModel
        toolBarModel?.degrees = photoDegrees
        
        let imageSize = ImageViewer.imageSize(image, degrees: photoDegrees)
        let (newScale, newOffset) = ImageViewer.zoomToFit(with: containerSize, image: image, degrees: photoDegrees)
        self._model = State(wrappedValue: ImageViewerModel(
            offset: newOffset, 
            scale: newScale,
            degrees: photoDegrees,
            imageSize: imageSize
        ))
    }
    
    let id: UUID
    let image: AKImage
    let containerSize: CGSize
    let contentMode: ContentMode
    let toolBarModel: GameToolBarModel?
    
    @State private var model: ImageViewerModel
    
    // Computed property to get current degrees from toolbar or model cache
    private var currentDegrees: Double {
        toolBarModel?.degrees ?? model.degrees
    }
        
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.ignoresSafeArea()

            if contentMode == .fill {
                Image(akImage: image)
                    .resizable()
                    .rotationEffect(Angle(degrees: currentDegrees))
                    .aspectRatio(contentMode: .fill)
                    .frame(width: containerSize.width, height: containerSize.height, alignment: .center)
            } else {
                Image(akImage: image)
                    .scaleEffect(model.scale)
                    .rotationEffect(Angle(degrees: currentDegrees))
                    .offset(x: model.offset.x, y: model.offset.y)
                    .frame(width: model.currentSize.width, height: model.currentSize.height)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .leading)
#if !os(tvOS)
        .dragTapGesture(pressAction: pressAction(_:), doubleTapAction: doubleTapAction(_:), dragStartAction: dragStartAction(_:), dragAction: dragAction(_:), dragEndAction: dragEndAction(_:), endAction: endAction(_:), magnifierAction: magnifierAction(_:isFirst:))
#endif
        .onChange(of: toolBarModel?.degrees) { _, _ in
            resetZoom()
        }
        .task(id: id) {
            resetZoom(withoutAnimation: true)
        }
    }
}

// MARK: - Zooming

private extension ImageViewer {
    static func zoomToFit(with size: CGSize, image: AKImage, degrees: Double) -> (CGFloat, CGPoint) {
        let scale = normScale(screenSize: size, image: image, degrees: degrees)
        let imgSize = imageSize(image, degrees: degrees)
        let x = (size.width - imgSize.width * scale) / 2.0
        let y = (size.height - imgSize.height * scale) / 2.0
        let offset = CGPoint(x: x, y: y)
        return (scale, offset)
    }
    
    static func normScale(screenSize: CGSize, image: AKImage, degrees: Double) -> CGFloat {
        let size = imageSize(image, degrees: degrees)
        let wScale = screenSize.width / size.width
        let hScale = screenSize.height / size.height
        return min(wScale, hScale)
    }
    
    static func imageSize(_ image: AKImage, degrees: Double) -> CGSize {
        let normalised = degrees.truncatingRemainder(dividingBy: 360)
        return (normalised == 0 || normalised == 180) ? image.fixedSize : CGSize(width: image.size.height, height: image.size.width)
    }

    func resetZoom(withoutAnimation: Bool = false) {
        let degrees = currentDegrees
        let (newScale, newOffset) = ImageViewer.zoomToFit(with: containerSize, image: image, degrees: degrees)
        model.normScale = newScale
        model.updateDegrees(degrees, originalImageSize: image.fixedSize)
        zoom(scale: newScale, at: newOffset, withoutAnimation: withoutAnimation)
    }

    func zooming(on location: CGPoint) {
        let (newScale, newOffset): (CGFloat, CGPoint)
        if model.scale != model.normScale {
            let degrees = currentDegrees
            (newScale, newOffset) = ImageViewer.zoomToFit(with: containerSize, image: image, degrees: degrees)
        } else {
            (newScale, newOffset) = zoomIn(at: location)
        }
        zoom(scale: newScale, at: newOffset, withoutAnimation: false)
    }

    func zoom(scale: CGFloat, at offset: CGPoint, withoutAnimation: Bool) {
        if withoutAnimation {
            zoom(scale: scale, at: offset)
        } else {
            withAnimation {
                zoom(scale: scale, at: offset)
            }
        }
    }

    func zoom(scale: CGFloat, at offset: CGPoint) {
        model.scale = scale
        model.lastScale = model.scale
        model.offset = offset
        model.lastOffset = model.offset
    }

    func zoomIn(at point: CGPoint) -> (CGFloat, CGPoint) {
        let newScale = max(0.1, model.scale * 4)
        let offPoint = (point - model.offset) / model.scale
        
        updateScale(newScale, updateLast: false)
        
        let pswidth = (containerSize.width / newScale) / 2
        let psHeight = (containerSize.height / newScale) / 2
        let offset = CGPoint(x: -1 * (offPoint.x - pswidth) * model.scale, y: -1 * (offPoint.y - psHeight) * model.scale)
        return (newScale, offset)
    }
}

// MARK: - Gesture Magnifyer

private extension ImageViewer {
    func updateScale(_ value: CGFloat, updateLast: Bool) {
        if updateLast {
            model.lastScale = value
        }
        let delta = value / model.lastScale
        let newScale = model.scale * delta
        if newScale < 0.1 {
            return
        }
        
        let scaleDiff = (newScale - model.scale) / 2
        let imgOff = model.baseImageSize * scaleDiff
        let newOffsetNew = CGPoint(x: -imgOff.width, y: -imgOff.height)
        
        model.lastScale = value
        model.scale = newScale
        updateOffset(with: newOffsetNew, firstOffset: model.offset)
    }
}

// MARK: - Gesture Drag

private extension ImageViewer {
    func updateOffset(with newLocation: CGPoint, firstOffset: CGPoint) {
        let offX = max(300, (containerSize.width - model.currentSize.width) / 2)
        let offY = max(300, (containerSize.height - model.currentSize.height) / 2)
        let minX = containerSize.width - model.currentSize.width - offX
        let minY = containerSize.height - model.currentSize.height - offY
        
        var newOffset = firstOffset + newLocation
        newOffset.x = min(max(newOffset.x, minX), offX)
        newOffset.y = min(max(newOffset.y, minY), offY)
        
        model.lastOffset = firstOffset
        model.offset = newOffset
    }
    
}

// MARK: - Gesture Double Tap

private extension ImageViewer {
    func onDoubleTapped(with location: CGPoint) {
        zooming(on: location)
    }
}

#if !os(tvOS)
// MARK: - Gesture & updates

private extension ImageViewer {
    func pressAction(_ value: DragGesture.Value) {}
    
    func doubleTapAction(_ value: DragGesture.Value) {
        onDoubleTapped(with: value.location)
    }
    
    func dragStartAction(_ value: DragGesture.Value) {
        model.lastOffset = model.offset
    }
    
    func dragAction(_ value: DragGesture.Value) {
        updateOffset(with: value.location - value.startLocation, firstOffset: model.lastOffset)
    }
    
    func dragEndAction(_: DragGesture.Value) {}
    
    func endAction(_: DragGesture.Value) {}
    
    func magnifierAction(_ value: CGFloat, isFirst: Bool) {
        updateScale(value, updateLast: isFirst)
    }
}
#endif

@MainActor @Observable
fileprivate final class ImageViewerModel {
    init(offset: CGPoint = .zero, scale: CGFloat = 1, degrees: Double = 0, imageSize: CGSize = .zero) {
        self.offset = offset
        self.lastOffset = offset
        self.scale = scale
        self.lastScale = scale
        self.normScale = scale
        self.degrees = degrees
        self.baseImageSize = imageSize
    }
    
    var offset: CGPoint
    var lastOffset: CGPoint
    var scale: CGFloat
    var lastScale: CGFloat
    var normScale: CGFloat
    
    // Cache computed values
    var degrees: Double
    var baseImageSize: CGSize
    
    var currentSize: CGSize {
        baseImageSize * scale
    }
    
    func updateImageSize(_ size: CGSize) {
        baseImageSize = size
    }
    
    func updateDegrees(_ newDegrees: Double, originalImageSize: CGSize) {
        degrees = newDegrees
        let normalised = newDegrees.truncatingRemainder(dividingBy: 360)
        baseImageSize = (normalised == 0 || normalised == 180)
            ? originalImageSize
            : CGSize(width: originalImageSize.height, height: originalImageSize.width)
    }
}

//import RPGResourcesDebug
//
//#Preview {
//    ImageViewer(image: AKImage(named: ResourcesDebug.adventurePhoto, in: ResourcesDebug.bundle, with: nil)!, photoDegrees: 0, containerSize: CGSize(width: 380, height: 600), toolBarModel: GameToolBarModel())
//        .border(.red, width: 2)
//}
