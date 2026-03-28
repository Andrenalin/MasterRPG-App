// @copyright André Trettin


// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import GeneratorRPG
import SwiftUI

/// View displaying extracted PDF content with selectable properties
public struct BlocksPdfContentView: View {

    let content: [BlockGenModel]

    public init(content: [BlockGenModel]) {
        self.content = content
    }

    public var body: some View {
        Form {
            Section {
                Text("Select which extracted values you would like to apply on the PDF item.", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(content) { block in
                    Text(block.name)
                    Text(block.information)
                }
            }
        }
#if os(macOS)
        .formStyle(.grouped)
#endif
    }
}

#endif
