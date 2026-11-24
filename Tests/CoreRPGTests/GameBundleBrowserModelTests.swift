// @copyright André Trettin

#if !os(tvOS)
import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_TestGaps §5.15: the status machine of the game bundle browser. A download from a
/// private address is refused by `GuardedRemoteDownload` before it connects, so the failure path
/// runs without a network.
@MainActor
@Suite("Game bundle browser model")
struct GameBundleBrowserModelTests {
    private let privateBundle = URL(string: "http://127.0.0.1:9/Adventure.gmz")!

    @Test("It starts idle without a download")
    func startsIdle() {
        let model = GameBundleBrowserModel(loadsStartPage: false)

        #expect(model.status == .idle)
        #expect(model.downloadedFile == nil)
        #expect(!model.isDownloading)
    }

    @Test("A blocked navigation shows blocked, an allowed one clears it")
    func blockedAndAllowed() {
        let model = GameBundleBrowserModel(loadsStartPage: false)

        model.navigationBlocked()
        #expect(model.status == .blocked)
        model.navigationAllowed()
        #expect(model.status == .idle)
    }

    @Test("Starting a download shows the file name until it ends")
    func downloadingShowsTheName() async {
        let model = GameBundleBrowserModel(loadsStartPage: false)

        model.startDownload(of: privateBundle)

        #expect(model.status == .downloading("Adventure.gmz"))
        #expect(model.isDownloading)
        _ = await awaitCondition { !model.isDownloading }
    }

    @Test("Navigation events do not replace the status of a running download")
    func navigationDoesNotHideADownload() async {
        let model = GameBundleBrowserModel(loadsStartPage: false)
        model.startDownload(of: privateBundle)

        model.navigationBlocked()
        #expect(model.status == .downloading("Adventure.gmz"))
        model.navigationAllowed()
        #expect(model.status == .downloading("Adventure.gmz"))
        _ = await awaitCondition { !model.isDownloading }
    }

    @Test("A second download while one runs is ignored")
    func oneDownloadAtATime() async {
        let model = GameBundleBrowserModel(loadsStartPage: false)
        model.startDownload(of: privateBundle)

        model.startDownload(of: URL(string: "http://127.0.0.1:9/Other.gmz")!)

        #expect(model.status == .downloading("Adventure.gmz"))
        _ = await awaitCondition { !model.isDownloading }
    }

    @Test("A download from a private address fails, delivers no file and allows a new try")
    func privateAddressFails() async {
        let model = GameBundleBrowserModel(loadsStartPage: false)
        model.startDownload(of: privateBundle)

        let failed = await awaitCondition {
            if case .failed = model.status { return true }
            return false
        }

        #expect(failed, "status: \(model.status)")
        #expect(model.downloadedFile == nil)
        model.startDownload(of: privateBundle)
        #expect(model.status == .downloading("Adventure.gmz"), "the failed download is no longer in flight")
        _ = await awaitCondition { !model.isDownloading }
    }

    @Test("A cancelled download ends idle and a late result changes nothing")
    func cancelledDownloadStaysIdle() async {
        let model = GameBundleBrowserModel(loadsStartPage: false)
        model.startDownload(of: privateBundle)

        model.cancelDownload()

        #expect(model.status == .idle)
        let stayed = await conditionHolds(for: .milliseconds(300)) {
            model.status == .idle && model.downloadedFile == nil
        }
        #expect(stayed, "the cancelled download must not report its failure; status: \(model.status)")
    }

    @Test("Cancelling without a download changes nothing")
    func cancelWithoutDownload() {
        let model = GameBundleBrowserModel(loadsStartPage: false)
        model.navigationBlocked()

        model.cancelDownload()

        #expect(model.status == .blocked)
    }

    @Test("A new download after a cancel is not cancelled by the old one finishing")
    func replacedDownloadKeepsItsOwnStatus() async {
        let model = GameBundleBrowserModel(loadsStartPage: false)
        model.startDownload(of: privateBundle)
        model.cancelDownload()

        model.startDownload(of: URL(string: "http://127.0.0.1:9/Second.gmz")!)

        #expect(model.status == .downloading("Second.gmz"))
        let failed = await awaitCondition {
            if case .failed = model.status { return true }
            return false
        }
        #expect(failed, "the second download ran to its own end; status: \(model.status)")
    }
}
#endif
