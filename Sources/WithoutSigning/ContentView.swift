//
//  ContentView.swift
//  WithoutSigning
//
//  Created by Andre Trettin on 22/9/2568 BE.
//

@testable import CoreRPG
@testable import DiceRPG
import SwiftData
import SwiftUI

struct ContentView: View {
    @State var model: TextEditModel = .preview
    
    @Environment(\.modelContext) var modelContext
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                DiceRootFactory.rootView(withoutNavigation: true)
                    .environment(DiceRootFactory.rootModel(modelContext: modelContext))
                Text("Description")
                
                TextEditorLinkView(model: model)
                    .dropDestination(for: .dice) { name, itenId, entryId in
                        model.text.append("[\(name)](RPG://\(itenId))")
                        
                    }
     
                Button("Save") {
                    model.resetText()
                }
                
                Text(model.text)
                
                Rectangle().fill(Color.red.gradient)
                    .onTapGesture {
                        let text = "[2d20](RPG://DICE/0/\(UUID().uuidString)"
                        let attributedText = AttributedString(text)
                        model.attributedText.append(attributedText)
                    }
                    .draggable(for: .dice, itemId: UUID(), entryId: nil, name: "2d20")
            }
            .onChange(of: model.attributedText) {
                model.updateLinks()
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(try! ModelContainer(for: LinkDataModel.self, TagDataModel.self, DiceDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
}
