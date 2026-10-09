// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import Testing

@testable import GameRPG

@Suite("Game top safe area")
struct GameTopOcclusionTests {
    private let duoWidth: CGFloat = 466
    private let duoCamera = CGRect(x: 399.67, y: 29.33, width: 37, height: 37)
    private let duoCorner = CGRect(x: 382, y: 0, width: 84, height: 82)

    @Test("A camera block in the top trailing corner frees the top band")
    func trailingCornerBlockIsReclaimable() {
        let width = GameTopOcclusion.reclaimableCornerWidth(
            topInset: 82,
            screenWidth: duoWidth,
            occlusions: [duoCamera, duoCorner]
        )
        #expect(width == 84)
    }

    @Test("A centered cut-out keeps the top safe area")
    func centeredCutOutIsNotReclaimable() {
        let island = CGRect(x: 138, y: 14, width: 126, height: 37)
        let width = GameTopOcclusion.reclaimableCornerWidth(topInset: 62, screenWidth: 402, occlusions: [island])
        #expect(width == 0)
    }

    @Test("No occlusion or no top inset keeps the layout unchanged")
    func nothingToReclaim() {
        #expect(GameTopOcclusion.reclaimableCornerWidth(topInset: 24, screenWidth: 820, occlusions: []) == 0)
        #expect(GameTopOcclusion.reclaimableCornerWidth(topInset: 0, screenWidth: duoWidth, occlusions: [duoCorner]) == 0)
    }

    @Test("A top inset taller than the corner block stays")
    func insetBeyondCornerBlockIsNotReclaimable() {
        let width = GameTopOcclusion.reclaimableCornerWidth(topInset: 120, screenWidth: duoWidth, occlusions: [duoCorner])
        #expect(width == 0)
    }

    @Test("A block spanning most of the top edge is not a corner")
    func wideBlockIsNotReclaimable() {
        let wide = CGRect(x: 100, y: 0, width: 366, height: 82)
        #expect(GameTopOcclusion.reclaimableCornerWidth(topInset: 82, screenWidth: duoWidth, occlusions: [wide]) == 0)
    }
}
#endif
