// @copyright André Trettin

import SwiftUI

struct ImportInformationSection: View {
    var body: some View {
        GroupBoxTV {
            VStack(spacing: 16) {
                Text("Use the Free Support [Page](https://github.com/Andrenalin/MasterRPG)", bundle: .module)
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
