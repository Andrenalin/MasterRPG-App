// @copyright André Trettin

import SwiftUI

struct ImportInformationSection: View {
    /// Called with the `.gmz` file the in-app browser downloaded, to import it.
    var onBundleDownloaded: @MainActor (URL) -> Void = { _ in }

    #if !os(tvOS)
        @State private var showBrowser = false
    #endif

    var body: some View {
        GroupBoxTV {
            VStack(spacing: 16) {
                #if os(tvOS)
                    Text("Use the Free Support [Page](https://github.com/Andrenalin/MasterRPG)", bundle: .module)
                #else
                    Button {
                        showBrowser = true
                    } label: {
                        Label {
                            Text("Browse Free Game Bundles", bundle: .module)
                        } icon: {
                            Image(systemName: "globe")
                        }
                    }
                    .sheet(isPresented: $showBrowser) {
                        GameBundleBrowserView(onDownloaded: onBundleDownloaded)
                    }
                #endif
                Text("These are free packages ready to use. They will add tables with rules, photos, characters and adventures for a certain rule system.", bundle: .module)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } label: {
            Text("Download free game bundles", bundle: .module)
        }
    }
}

#Preview {
    ImportInformationSection()
        .padding()
}
