//
//  MenuBarView.swift
//  MasterRPG
//
//  Created by Andre Trettin on 24.09.25.
//


// @copyright André Trettin

import AudioRPG
import SwiftUI

struct MenuBarView: View {
    let audioRoot: AudioRootModel

    var body: some View {
        VStack {
            Text("Music in MasterRPG")

            Divider()

            AudioPlayerMenuBarView()
        }
        .padding()
        .environment(audioRoot)
    }
        
}
