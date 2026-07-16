//
//  GameBrowserView.swift
//  MasterRPG
//
//  Created by Andre Trettin on 16/6/2569 BE.
//

import SwiftUI
import Network

struct GameBrowserView: View {
    @State private var browserManager: BrowserManager = BrowserManager()
    private let startsServices: Bool

    init(startsServices: Bool = true) {
        self.startsServices = startsServices
    }

    var body: some View {
        VStack {
            if let errorMessage = browserManager.errorMessage {
                Text(errorMessage)
                Divider()
            }
            ForEach(browserManager.games) { game in
                Text("Found game: \(game.deviceName)", bundle: .module)
            }
        }
        .padding()
        .onAppear {
            guard startsServices else { return }
            browserManager.start()
        }
        .onDisappear {
            guard startsServices else { return }
            browserManager.stop()
        }
    }
}

#Preview(traits: .mockData) {
    GameBrowserView(startsServices: false)
}
