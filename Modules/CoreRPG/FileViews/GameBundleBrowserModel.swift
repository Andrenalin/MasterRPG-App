// @copyright André Trettin

#if !os(tvOS)
    import Foundation
    import Observation
    import WebKit

    /// Owns the web page of the game bundle browser and downloads the `.gmz` file a link points to.
    @MainActor @Observable
    final class GameBundleBrowserModel {
        enum Status: Equatable {
            case idle
            case downloading(String)
            case failed(String)
            case blocked
        }

        let page: WebPage
        private(set) var status: Status = .idle
        /// The downloaded bundle, ready for the import. Set once per finished download.
        private(set) var downloadedFile: URL?

        @ObservationIgnored private var downloadTask: Task<Void, Never>?
        /// Names the download in flight. A cancelled download that is replaced by a new one finishes
        /// later and must not clear the new one's task or status. See CODE_AUDIT_26 §3.4.
        @ObservationIgnored private var downloadToken: UUID?

        init() {
            let decider = GameBundleNavigationDecider()
            page = WebPage(navigationDecider: decider)
            decider.model = self
            page.load(GameBundleBrowserPolicy.startUrl)
        }

        var isDownloading: Bool {
            if case .downloading = status { return true }
            return false
        }

        func goBack() {
            guard let item = page.backForwardList.backList.last else { return }
            page.load(item)
        }

        func goForward() {
            guard let item = page.backForwardList.forwardList.first else { return }
            page.load(item)
        }

        /// GitHub opens a file from its listing with a client-side route change (history API): no
        /// navigation action reaches the decider, only the page URL changes. A bundle page is
        /// turned into a download and the browser steps back to the listing.
        func pageUrlChanged(_ url: URL?) {
            guard let url, case .download(let fileUrl) = GameBundleBrowserPolicy.decision(for: url) else { return }
            startDownload(of: fileUrl)
            goBack()
        }

        func navigationAllowed() {
            guard !isDownloading else { return }
            status = .idle
        }

        func navigationBlocked() {
            guard !isDownloading else { return }
            status = .blocked
        }

        func startDownload(of url: URL) {
            guard downloadTask == nil else { return }
            status = .downloading(url.lastPathComponent)
            let token = UUID()
            downloadToken = token
            downloadTask = Task { [weak self] in
                let result = await Result { try await Self.download(url) }
                guard let self, downloadToken == token else { return }
                downloadTask = nil
                downloadToken = nil
                switch result {
                case .success(let fileUrl):
                    status = .idle
                    downloadedFile = fileUrl
                case .failure(let error):
                    status = error is CancellationError ? .idle : .failed(error.localizedDescription)
                }
            }
        }

        func cancelDownload() {
            downloadTask?.cancel()
            downloadTask = nil
            downloadToken = nil
            if isDownloading { status = .idle }
        }

        @concurrent
        private static func download(_ url: URL) async throws -> URL {
            // Capped while it transfers, redirects to non-public hosts refused, the status
            // checked and a stalled transfer given up after minutes, not the shared session's
            // days. See CODE_AUDIT §6.3.
            let temporaryUrl = try await GuardedRemoteDownload.download(from: url, maximumBytes: ByteLimits.maximumSourceFileBytes)
            // The import wants the file name, so keep it in a folder of its own.
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let fileUrl = folder.appending(path: url.lastPathComponent, directoryHint: .notDirectory)
            try FileManager.default.moveItem(at: temporaryUrl, to: fileUrl)
            return fileUrl
        }
    }

    /// Keeps the browser inside the repository and turns bundle links into downloads.
    @MainActor
    final class GameBundleNavigationDecider: WebPage.NavigationDeciding {
        weak var model: GameBundleBrowserModel?

        func decidePolicy(
            for action: WebPage.NavigationAction,
            preferences: inout WebPage.NavigationPreferences
        ) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            switch GameBundleBrowserPolicy.decision(for: url) {
            case .allow:
                model?.navigationAllowed()
                return .allow
            case .download(let fileUrl):
                model?.startDownload(of: fileUrl)
                return .cancel
            case .block:
                model?.navigationBlocked()
                return .cancel
            }
        }
    }
#endif
