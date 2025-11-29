// @copyright André Trettin

import SwiftUI

public struct SplitContentUnavailable: View {
    public init(module: NetworkModules) {
        self.module = module
    }
    
    let module: NetworkModules
    
    public var body: some View {
        let _ = Self._printChanges()

        ContentUnavailableView {
            Label {
                Text("No \(module.localizedTitle) selected", bundle: .module)
            } icon: {
                Image(systemName: module.icon)
            }
        } description: {
            Text("Choose an item to see more details", bundle: .module)
        }
    }
}
