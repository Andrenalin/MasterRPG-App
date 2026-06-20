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
    /// The network task to cancel the `NetworkBrowser`.
    @State private var networkTask: Task<Void, Error>?

    var body: some View {
        VStack {
            startBrowsingView
            
            ForEach(browserManager.games.list) { start in
                Text(" Got - \(start.endpoint.name)")
            }
        }
    }
    
    var startBrowsingView: some View {
        VStack {
            if let errorMessage = browserManager.errorMessage {
                Text(errorMessage)
                Divider()
            }
            
            Button("Start browsing") {
                // As long as the state isn't currently connecting, start the connection.
                guard browserManager.connectionState != .connecting else { return }
                networkTask = browserManager.start()
            }
            
        }
        .padding()
    }
}
