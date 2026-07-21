// @copyright André Trettin

import CoreRPG
import SwiftUI

struct LogRowsSection: View {
    let logController: LogGameController

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        Section {
            ForEach(logController.logRows) { row in
                LogMessageRow(row: row)
                    .equatable()
            }
        } header: {
            Text("Message Logs", bundle: .module)
        }
    }
}

#Preview {
    List {
        LogRowsSection(logController: .preview)
    }
}
