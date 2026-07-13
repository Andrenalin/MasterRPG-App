// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import GeneratorRPG
import SwiftUI

/// View displaying extracted PDF content with selectable properties
public struct ContentBlocksView: View {

    let content: [BlockEntryGenModel]

    public init(content: [BlockEntryGenModel]) {
        self.content = content
    }

    public var body: some View {
        Form {
            Section {
                ForEach(content) { block in
                    Text(block.title)
                    Text(block.content)
                }
            }
        }
#if os(macOS)
        .formStyle(.grouped)
#endif


    }
}

#Preview {
    ContentBlocksView(content: [
        BlockEntryGenModel(
            title: "The Forgotten Shrine",
            content: "A weathered stone doorway leads into a quiet underground chamber."
        )
    ])
}

#endif
