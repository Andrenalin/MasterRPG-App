//
//  ItemController.swift
//  MasterRPG
//
//  Created by Andre Trettin on 15.07.25.
//

import CoreRPG
import Foundation
import SwiftData

struct ItemController: ItemControllable {
    func item(for: UUID) async -> PhotoModel? {
        nil
    }
    
    func itemSync(for: UUID) -> PhotoModel? {
        nil
    }
    
    typealias Model = PhotoModel
    
    func allItemIds() -> [UUID] {
        []
    }
    
    func fileUrl(for: UUID) async -> FileUrl? {
        nil
    }
    

}
