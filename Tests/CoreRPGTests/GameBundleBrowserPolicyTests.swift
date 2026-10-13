// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@Suite("Game bundle browser policy")
struct GameBundleBrowserPolicyTests {
    private func decision(_ string: String) -> GameBundleBrowserPolicy {
        guard let url = URL(string: string) else { return .block }
        return GameBundleBrowserPolicy.decision(for: url)
    }

    @Test("Repository pages stay in the browser")
    func repositoryPagesAreAllowed() {
        #expect(decision("https://github.com/Andrenalin/MasterRPG") == .allow)
        #expect(decision("https://github.com/Andrenalin/MasterRPG/tree/main/DungeonSlayers") == .allow)
        #expect(decision("https://github.com/andrenalin/masterrpg/blob/main/README.md") == .allow)
    }

    @Test("Pages outside the repository are blocked")
    func foreignPagesAreBlocked() {
        #expect(decision("https://github.com/Andrenalin") == .block)
        #expect(decision("https://github.com/Andrenalin/OtherRepo") == .block)
        #expect(decision("https://github.com/Andrenalin/MasterRPGFork") == .block)
        #expect(decision("https://github.com/login") == .block)
        #expect(decision("https://example.com/Andrenalin/MasterRPG") == .block)
        #expect(decision("http://github.com/Andrenalin/MasterRPG") == .block)
        #expect(decision("https://github.com.evil.example/Andrenalin/MasterRPG/raw/main/a.gmz") == .block)
    }

    @Test("A blob link of a bundle downloads its raw file")
    func blobLinkDownloadsRawFile() {
        #expect(
            decision("https://github.com/Andrenalin/MasterRPG/blob/main/DungeonSlayers/English/Adventure/Ruin%20of%20Madness.gmz?raw=true")
                == .download(URL(string: "https://github.com/Andrenalin/MasterRPG/raw/main/DungeonSlayers/English/Adventure/Ruin%20of%20Madness.gmz")!)
        )
        #expect(
            decision("https://github.com/Andrenalin/MasterRPG/raw/main/Rules.GMZ")
                == .download(URL(string: "https://github.com/Andrenalin/MasterRPG/raw/main/Rules.GMZ")!)
        )
    }

    @Test("Bundles of other repositories are blocked")
    func foreignBundlesAreBlocked() {
        #expect(decision("https://github.com/Other/Repo/blob/main/a.gmz") == .block)
        #expect(decision("https://raw.githubusercontent.com/Other/Repo/main/a.gmz") == .block)
        #expect(decision("https://media.githubusercontent.com/media/Other/Repo/main/a.gmz") == .block)
        #expect(decision("https://example.com/a.gmz") == .block)
    }

    @Test("Redirect targets of the repository are bundle downloads")
    func redirectTargetsDownload() {
        let raw = "https://raw.githubusercontent.com/Andrenalin/MasterRPG/main/a.gmz"
        #expect(decision(raw) == .download(URL(string: raw)!))
        let media = "https://media.githubusercontent.com/media/Andrenalin/MasterRPG/main/a.gmz"
        #expect(decision(media) == .download(URL(string: media)!))
        #expect(decision("https://raw.githubusercontent.com/Andrenalin/MasterRPG/main/README.md") == .block)
    }
}
