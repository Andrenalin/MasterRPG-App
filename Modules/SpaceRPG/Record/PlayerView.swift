/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The view that plays the input video.
*/

#if os(iOS) && !targetEnvironment(simulator)

import AVKit
import SwiftUI

struct PlayerView: UIViewRepresentable {

    /// The location of a video asset.
    let url: URL

    /// A Boolean value that indicates whether the video contains transparent pixesl.
    let isTransparent: Bool

    /// A Boolean value that indicates whether the video contains an alpha mask below it.
    let isStacked: Bool

    /// A Boolean value that indicates whether the video's image is inverted.
    let isInverted: Bool

    /// A Boolean value that indicates whether the player view loops the video.
    let shouldLoop: Bool

    private nonisolated static let videoSize = CGSize(width: 1280, height: 1080).applying(CGAffineTransformIdentity)
    private static let transparentPixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

    @MainActor
    final class Coordinator {
        var playerLooper: AVPlayerLooper?
        var loadingTask: Task<Void, Never>?
        var url: URL?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.playerLayer?.videoGravity = .resizeAspect
        playerView.playerLayer?.pixelBufferAttributes = isTransparent ? Self.transparentPixelBufferAttributes : nil
        loadPlayer(in: playerView, coordinator: context.coordinator)

        return playerView
    }

    func updateUIView(_ playerView: AVPlayerView, context: Context) {
        if context.coordinator.url != url {
            loadPlayer(in: playerView, coordinator: context.coordinator)
        } else {
            playerView.player?.play()
        }
    }

    private func loadPlayer(in playerView: AVPlayerView, coordinator: Coordinator) {
        coordinator.loadingTask?.cancel()
        coordinator.url = url

        let url = url
        let isStacked = isStacked
        let isInverted = isInverted
        let shouldLoop = shouldLoop

        coordinator.loadingTask = Task { @MainActor [weak playerView, weak coordinator] in
            let playerItem = AVPlayerItem(url: url)
            playerItem.videoComposition = try? await Self.createVideoComposition(
                for: playerItem.asset,
                isStacked: isStacked,
                isInverted: isInverted
            )

            guard !Task.isCancelled,
                  let playerView,
                  let coordinator,
                  coordinator.url == url else {
                return
            }

            let player = AVQueuePlayer(playerItem: playerItem)
            player.actionAtItemEnd = .pause
            coordinator.playerLooper = shouldLoop
                ? AVPlayerLooper(player: player, templateItem: playerItem)
                : nil
            playerView.player = player
            player.play()
        }
    }

    private nonisolated static func createVideoComposition(
        for asset: AVAsset,
        isStacked: Bool,
        isInverted: Bool
    ) async throws -> AVVideoComposition {
        let size = PlayerView.videoSize
        let videoSize: CGSize = isStacked ? CGSize(width: size.width, height: size.height / 2.0) : size
        let filteredComposition = try await AVVideoComposition(applyingFiltersTo: asset) { parameters in
            let image = filteredImage(
                parameters.sourceImage,
                videoSize: videoSize,
                isStacked: isStacked,
                isInverted: isInverted
            )
            return AVCIImageFilteringResult(resultImage: image)
        }

        let configuration = AVVideoComposition.Configuration(
            animationTool: filteredComposition.animationTool,
            colorPrimaries: filteredComposition.colorPrimaries,
            colorTransferFunction: filteredComposition.colorTransferFunction,
            colorYCbCrMatrix: filteredComposition.colorYCbCrMatrix,
            customVideoCompositorClass: filteredComposition.customVideoCompositorClass,
            frameDuration: filteredComposition.frameDuration,
            instructions: filteredComposition.instructions,
            outputBufferDescription: filteredComposition.outputBufferDescription,
            perFrameHDRDisplayMetadataPolicy: filteredComposition.perFrameHDRDisplayMetadataPolicy,
            renderScale: filteredComposition.renderScale,
            renderSize: videoSize,
            sourceSampleDataTrackIDs: filteredComposition.sourceSampleDataTrackIDs,
            sourceTrackIDForFrameTiming: filteredComposition.sourceTrackIDForFrameTiming,
            spatialVideoConfigurations: filteredComposition.spatialVideoConfigurations
        )
        return AVVideoComposition(configuration: configuration)
    }

    private nonisolated static func filteredImage(
        _ sourceImage: CIImage,
        videoSize: CGSize,
        isStacked: Bool,
        isInverted: Bool
    ) -> CIImage {
        let filterName = isStacked ? "CIBlendWithMask" : "CIMaskToAlpha"
        guard let filter = CIFilter(name: filterName) else {
            return sourceImage
        }

        if isStacked {
            let sourceRect = CGRect(origin: .zero, size: videoSize)
            let alphaRect = sourceRect.offsetBy(dx: 0, dy: sourceRect.height)
            let transform = CGAffineTransform(translationX: 0, y: -sourceRect.height)
            let inputImage = sourceImage.cropped(to: alphaRect).transformed(by: transform)
            let maskImage = sourceImage.cropped(to: sourceRect)
            let backgroundImage = CIImage(color: .clear).cropped(to: inputImage.extent)
            filter.setValue(inputImage, forKey: kCIInputImageKey)
            filter.setValue(maskImage, forKey: kCIInputMaskImageKey)
            filter.setValue(backgroundImage, forKey: kCIInputBackgroundImageKey)
        } else {
            filter.setValue(sourceImage, forKey: kCIInputImageKey)
        }

        guard let outputImage = filter.outputImage else {
            return sourceImage
        }
        return isInverted ? outputImage.applyingFilter("CIColorInvert") : outputImage
    }
}

class AVPlayerView: UIView {
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    /// Safe by construction: `layerClass` above guarantees `layer` is always backed by an
    /// `AVPlayerLayer`, cached once here instead of re-deriving the cast on every access.
    fileprivate lazy var playerLayer: AVPlayerLayer? = layer as? AVPlayerLayer

    var player: AVPlayer? {
        get { playerLayer?.player }
        set { playerLayer?.player = newValue }
    }
}

#endif
