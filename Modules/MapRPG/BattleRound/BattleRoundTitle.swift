// @copyright André Trettin

import SwiftUI

struct BattleRoundTitle: View {
    let round: Int

    var body: some View {
        if round == 0 {
            Text("Surprise", bundle: .module)
        } else {
            Text("Round \(round)", bundle: .module)
        }
    }
}
