// @copyright André Trettin

import Foundation

/// Decides which pages the in-app game bundle browser may show and which links are bundle downloads.
/// Pure, so it is unit-testable without WebKit.
enum GameBundleBrowserPolicy: Equatable {
    /// Show the page in the browser.
    case allow
    /// Cancel the navigation and download this `.gmz` file for importing.
    case download(URL)
    /// Cancel the navigation; the page is outside the repository.
    case block

    static let owner = "Andrenalin"
    static let repository = "MasterRPG"
    static let fileExtension = "gmz"

    /// A constant literal, so the force unwrap cannot fail.
    static let startUrl = URL(string: "https://github.com/Andrenalin/MasterRPG")!

    static func decision(for url: URL) -> GameBundleBrowserPolicy {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else { return .block }
        let components = Array(url.pathComponents.dropFirst())
        let isBundle = url.pathExtension.lowercased() == fileExtension

        switch host {
        case "github.com":
            guard isRepository(components) else { return .block }
            guard isBundle else { return .allow }
            // `blob` is the viewer page of a file, `raw` redirects to its content (Git LFS included).
            guard components.count > 4, ["blob", "raw"].contains(components[2]) else { return .block }
            var rawComponents = components
            rawComponents[2] = "raw"
            return rawUrl(host: host, components: rawComponents).map { .download($0) } ?? .block
        case "raw.githubusercontent.com":
            return isBundle && isRepository(components) ? .download(url) : .block
        case "media.githubusercontent.com":
            // LFS content lives at /media/<owner>/<repository>/...
            guard components.first == "media" else { return .block }
            return isBundle && isRepository(Array(components.dropFirst())) ? .download(url) : .block
        default:
            return .block
        }
    }

    private static func isRepository(_ components: [String]) -> Bool {
        guard components.count >= 2 else { return false }
        return components[0].lowercased() == owner.lowercased()
            && components[1].lowercased() == repository.lowercased()
    }

    private static func rawUrl(host: String, components: [String]) -> URL? {
        var url = URL(string: "https://\(host)")
        for component in components {
            url?.append(path: component)
        }
        return url
    }
}
