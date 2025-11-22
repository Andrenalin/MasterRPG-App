//// @copyright André Trettin
//
//import CoreRPG
//import SwiftUI
//
//struct ImageViewer: View {
//    init(image: AKImage, photoDegrees: Double, containerSize: CGSize, toolBarModel: GameToolBarModel) {
//        self.image = image
//        self.containerSize = containerSize
//        self.toolBarModel = toolBarModel
//        toolBarModel.degrees = photoDegrees
//        
//        let (newScale, newOffset) = ImageViewer.zoomToFit(with: containerSize, image: image, degrees: photoDegrees)
//        self._model = State(wrappedValue: ImageViewerModel(offset: newOffset, scale: newScale))
//    }
//    
//    let image: AKImage
//    let containerSize: CGSize
//    let toolBarModel: GameToolBarModel
//    
//    @State private var model: ImageViewerModel
//        
//    var body: some View {
//        let _ = Self._printChanges()
//        ZStack(alignment: .topLeading) {
//            Color.clear.ignoresSafeArea()
//
//            Image(akImage: image)
//                .scaleEffect(model.scale)
//                .rotationEffect(Angle(degrees: toolBarModel.degrees))
//                .offset(x: model.offset.x, y: model.offset.y)
//                .contentMargins(.all, 50)
//                .frame(width: currentSize.width, height: currentSize.height)
//        }
//        .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
//#if !os(tvOS)
//        .dragTapGesture(pressAction: pressAction(_:), doubleTapAction: doubleTapAction(_:), dragStartAction: dragStartAction(_:), dragAction: dragAction(_:), dragEndAction: dragEndAction(_:), endAction: endAction(_:), magnifierAction: magnifierAction(_:isFirst:))
//#endif
//        .onChange(of: toolBarModel.degrees) {
//            resetZoom()
//        }
//        .onAppear {
//            resetZoom(withoutAnimation: true)
//        }
//    }
//}
//
//// MARK: - Zooming
//
//private extension ImageViewer {
//    static func zoomToFit(with size: CGSize, image: AKImage, degrees: Double) -> (CGFloat, CGPoint) {
//        let scale = normScale(screenSize: size, image: image, degrees: degrees)
//        let imgSize = imageSize(image, degrees: degrees)
//        let x = (size.width - imgSize.width * scale) / 2.0
//        let y = (size.height - imgSize.height * scale) / 2.0
//        let offset = CGPoint(x: x, y: y)
//        return (scale, offset)
//    }
//    
//    static func normScale(screenSize: CGSize, image: AKImage, degrees: Double) -> CGFloat {
//        let size = imageSize(image, degrees: degrees)
//        let wScale = screenSize.width / size.width
//        let hScale = screenSize.height / size.height
//        return min(wScale, hScale)
//    }
//    
//    static func imageSize(_ image: AKImage, degrees: Double) -> CGSize {
//        (degrees == 0 || degrees == 180) ? image.fixedSize : CGSize(width: image.size.height, height: image.size.width)
//    }
//    
//    var currentSize: CGSize {
//        ImageViewer.imageSize(image, degrees: toolBarModel.degrees) * model.scale
//    }
//
//    func resetZoom(withoutAnimation: Bool = false) {
//        let (newScale, newOffset): (CGFloat, CGPoint)
//        (newScale, newOffset) = ImageViewer.zoomToFit(with: containerSize, image: image, degrees: toolBarModel.degrees)
//        model.normScale = newScale
//        zoom(scale: newScale, at: newOffset, withoutAnimation: withoutAnimation)
//    }
//
//    func zooming(on location: CGPoint) {
//        let (newScale, newOffset): (CGFloat, CGPoint)
//        if model.scale != model.normScale {
//            (newScale, newOffset) = ImageViewer.zoomToFit(with: containerSize, image: image, degrees: toolBarModel.degrees)
//        } else {
//            (newScale, newOffset) = zoomIn(at: location)
//        }
//        zoom(scale: newScale, at: newOffset, withoutAnimation: false)
//    }
//
//    func zoom(scale: CGFloat, at offset: CGPoint, withoutAnimation: Bool) {
//        if withoutAnimation {
//            zoom(scale: scale, at: offset)
//        } else {
//            withAnimation {
//                zoom(scale: scale, at: offset)
//            }
//        }
//    }
//
//    func zoom(scale: CGFloat, at offset: CGPoint) {
//        model.scale = scale
//        model.lastScale = model.scale
//        model.offset = offset
//        model.lastOffset = model.offset
//    }
//
//    func zoomIn(at point: CGPoint) -> (CGFloat, CGPoint) {
//        let newScale = max(0.1, model.scale * 4)
//        let offPoint = (point - model.offset) / model.scale
//        
//        updateScale(newScale, updateLast: false)
//        
//        let pswidth = (containerSize.width / newScale) / 2
//        let psHeight = (containerSize.height / newScale) / 2
//        let offset = CGPoint(x: -1 * (offPoint.x - pswidth) * model.scale, y: -1 * (offPoint.y - psHeight) * model.scale)
//        return (newScale, offset)
//    }
//}
//
//// MARK: - Gesture Magnifyer
//
//private extension ImageViewer {
//    func updateScale(_ value: CGFloat, updateLast: Bool) {
//        if updateLast {
//            model.lastScale = value
//        }
//        let delta = value / model.lastScale
//        let newScale = model.scale * delta
//        if newScale < 0.1 {
//            return
//        }
//        
//        let imgSize = ImageViewer.imageSize(image, degrees: toolBarModel.degrees)
//        let scaleDiff = (newScale - model.scale) / 2
//        let imgOff = imgSize * scaleDiff
//        let newOffsetNew = CGPoint(x: -imgOff.width, y: -imgOff.height)
//        
//        model.lastScale = value
//        model.scale = newScale
//        updateOffset(with: newOffsetNew, firstOffset: model.offset)
//    }
//}
//
//// MARK: - Gesture Drag
//
//private extension ImageViewer {
//    func updateOffset(with newLocation: CGPoint, firstOffset: CGPoint) {
//        let imgSize = ImageViewer.imageSize(image, degrees: toolBarModel.degrees)
//        let offX = max(300, (containerSize.width - imgSize.width * model.scale) / 2)
//        let offY = max(300, (containerSize.height - imgSize.height * model.scale) / 2)
//        let minX = containerSize.width - (imgSize.width * model.scale) - offX
//        let minY = containerSize.height - (imgSize.height * model.scale) - offX
//        var newOffset = firstOffset + newLocation
//        if newOffset.x < minX {
//            newOffset.x = minX
//        }
//        if newOffset.x > offX {
//            newOffset.x = offX
//        }
//        if newOffset.y < minY {
//            newOffset.y = minY
//        }
//        if newOffset.y > offY {
//            newOffset.y = offY
//        }
//        model.lastOffset = firstOffset
//        model.offset = newOffset
//    }
//    
//    func translate(from location: CGPoint) -> CGPoint {
//        let imgSize = ImageViewer.imageSize(image, degrees: toolBarModel.degrees)
//        var newOffset = (location - model.offset) / model.scale
//        if newOffset.x < 0 {
//            newOffset.x = 0
//        }
//        if newOffset.x > imgSize.width {
//            newOffset.x = imgSize.width
//        }
//        if newOffset.y < 0 {
//            newOffset.y = 0
//        }
//        if newOffset.y > imgSize.height {
//            newOffset.y = imgSize.height
//        }
//        return newOffset
//    }
//}
//
//// MARK: - Gesture Double Tap
//
//private extension ImageViewer {
//    func onDoubleTapped(with location: CGPoint) {
//        zooming(on: location)
//    }
//}
//
//#if !os(tvOS)
//// MARK: - Gesture & updates
//
//private extension ImageViewer {
//    func pressAction(_ value: DragGesture.Value) {}
//    
//    func doubleTapAction(_ value: DragGesture.Value) {
//        onDoubleTapped(with: value.location)
//    }
//    
//    func dragStartAction(_ value: DragGesture.Value) {
//        model.lastOffset = model.offset
//    }
//    
//    func dragAction(_ value: DragGesture.Value) {
//        updateOffset(with: value.location - value.startLocation, firstOffset: model.lastOffset)
//    }
//    
//    func dragEndAction(_: DragGesture.Value) {}
//    
//    func endAction(_: DragGesture.Value) {}
//    
//    func magnifierAction(_ value: CGFloat, isFirst: Bool) {
//        updateScale(value, updateLast: isFirst)
//    }
//}
//#endif
//
//@Observable
//fileprivate final class ImageViewerModel {
//    init(offset: CGPoint = .zero, scale: CGFloat = 1) {
//        self.offset = offset
//        self.lastOffset = offset
//        self.scale = scale
//        self.lastScale = scale
//        normScale = scale
//    }
//    
//    var offset: CGPoint
//    var lastOffset: CGPoint
//    var scale: CGFloat
//    var lastScale: CGFloat
//    
//    var normScale: CGFloat
//}
//
////import RPGResourcesDebug
////
////#Preview {
////    ImageViewer(image: AKImage(named: ResourcesDebug.adventurePhoto, in: ResourcesDebug.bundle, with: nil)!, photoDegrees: 0, containerSize: CGSize(width: 380, height: 600), toolBarModel: GameToolBarModel())
////        .border(.red, width: 2)
////}
