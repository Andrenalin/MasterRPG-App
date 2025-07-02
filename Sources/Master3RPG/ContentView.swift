//
//  ContentView.swift
//  Master3RPG
//
//  Created by Andre Trettin on 02.07.25.
//

import SwiftUI
import SwiftData
import AndrenalinKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [PhotoDataModel]

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.name)")
                    } label: {
                        Text(item.name.wrappedValue)
                    }
                }
                .onDelete(perform: deleteItems)
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
#endif
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Text("Select an item")
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = PhotoDataModel(name: "Hello")
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: PhotoDataModel.self, inMemory: true)
}
