// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData


struct ItemController: ItemControllable, Sendable {

    let container: ModelContainer
    let collectionCategory: ItemListCategory = .playlist
}
