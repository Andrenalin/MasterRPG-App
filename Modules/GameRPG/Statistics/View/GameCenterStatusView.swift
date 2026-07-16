// @copyright André Trettin

import SwiftUI

struct GameCenterStatusView: View {
    @Bindable var model: GameCenterModel
    let controller: GameCenterController

    var body: some View {
        HStack {
            Image(
                systemName: model.isAuthenticated
                    ? "person.crop.circle.badge.checkmark"
                    : "person.crop.circle.badge.questionmark"
            )
            .imageScale(.large)
            .foregroundStyle(model.isAuthenticated ? .green : .secondary)
            VStack(alignment: .leading) {
                Text("Game Center", bundle: .module)
                    .bold()
                if model.isAuthenticated {
                    Text(model.playerName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Sign in to earn achievements.", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.isReportingAchievements {
                ProgressView()
            } else if !model.isAuthenticated {
                Button {
                    controller.authenticate()
                } label: {
                    Label {
                        Text("Sign In", bundle: .module)
                    } icon: {
                        Image(systemName: "gamecontroller")
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let model = GameCenterModel()
    GameCenterStatusView(model: model, controller: GameCenterController(model: model))
        .padding()
}
