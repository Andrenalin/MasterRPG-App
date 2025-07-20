//
//  MultiSelectionView.swift
//  PhotoRPG
//
//  Created by Andre Trettin on 20.07.25.
//

import SwiftUI
import SwiftData

struct MultiSelectionView: View {
    @Query(sort: [SortDescriptor(\PhotoDataModel.name)]) var photos: [PhotoDataModel]
    @Environment(\.modelContext) private var modelContext
    @State private var selection = Set<UUID>()
    @State private var editMode: EditMode = .inactive
    @State private var showActionSheet = false
    @State private var actionSheetPhoto: PhotoDataModel?
    
    var body: some View {
        NavigationStack {
            List(photos, selection: $selection) { photo in
                HStack {
                    Text(photo.name.isEmpty ? "Unnamed Photo" : photo.name)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onLongPressGesture {
                    selectOrToggle(photo)
                    actionSheetPhoto = photo
                    showActionSheet = true
                }
            }
            .confirmationDialog("Actions", isPresented: $showActionSheet, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    deleteSelectedPhotos()
                }
                Button("Cancel", role: .cancel) {}
            }
            .navigationTitle("Photos")
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(editMode == .active ? "Done" : "Select") {
                        editMode = editMode == .active ? .inactive : .active
                        if editMode == .inactive {
                            selection.removeAll()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !selection.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                deleteSelectedPhotos()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }
    
    private func deleteSelectedPhotos() {
        for id in selection {
            if let photo = photos.first(where: { $0.id == id }) {
                modelContext.delete(photo)
            }
        }
        try? modelContext.save()
        selection.removeAll()
    }
    
    private func selectOrToggle(_ photo: PhotoDataModel) {
        if !selection.contains(photo.id) {
            selection = [photo.id]
        }
    }
}

#Preview(traits: .mockData) {
    MultiSelectionView()
}
