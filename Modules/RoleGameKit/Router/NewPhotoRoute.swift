//
//  NewPhotoRoute.swift
//  PhotoRPG
//
//  Created by Andre Trettin on 9/7/2568 BE.
//

import CoreRPG
import Foundation
import PhotoRPG
import RPGPhotos
import SwiftUI

struct NewPhotoRoute: View {
    let appStore: AppStore
    let tabId: UUID
    let isExtended: Bool

    @State private var cacheModel = CacheItemListModel()
    @State private var deviceRotationModel = DeviceRotationModel()
    @State private var searchModel = SearchModel()
    @State private var tabTitleModel = TabTitleModel()

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if appStore.isNewUICode {
            PhotoRootView(withoutNavigation: isExtended)
                .environment(cacheModel)
                .environment(deviceRotationModel)
                .environment(searchModel)
                .environment(tabTitleModel)
                .task {
                    try? await Task.sleep(for: .seconds(3))
                    await DBConverter.convert(appStore: appStore, modelContext: modelContext)
                }
        } else {
            if isExtended {
                PhotoFactory.rootExtendedView(for: appStore.photoRoot, tabId: tabId)
                    .environment(appStore.photoRoot)
            } else {
                PhotoFactory.rootView(for: appStore.photoRoot, tabId: tabId)
                    .environment(appStore.photoRoot)
            }
        }
    }
}
