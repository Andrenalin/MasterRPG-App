//// @copyright André Trettin
//
//import AndrenalinKit
//import Foundation
//import SwiftData
//
//@Model
//final public class RPGDice: SwiftDataType {
//    init(uuid: UUID = UUID(), name: String? = nil, information: String? = nil, diceCategory: String = "", tags: String? = nil, displayState: Int32 = 0, addDiceEvery: Int16 = 0, compareOption: Int16 = 0, compareValue: Float = 0.0, coupOnlyOnFirstDie: Bool = false, coupValues: String = "", dice: String? = nil, diceUpdate: String = "", fumbleOnlyOnFirstDie: Bool = false, fumbleValues: String = "", modifier: Float = 0.0, percentDice: Bool = false, reorderDice: Bool = false, rerollOptions: String = "", sumUp: Bool = true) {
//        self.uuid = uuid
//        self.name = name
//        self.information = information
//        self.diceCategory = diceCategory
//        self.tags = tags
//        self.displayState = displayState
//        self.addDiceEvery = addDiceEvery
//        self.compareOption = compareOption
//        self.compareValue = compareValue
//        self.coupOnlyOnFirstDie = coupOnlyOnFirstDie
//        self.coupValues = coupValues
//        self.dice = dice
//        self.diceUpdate = diceUpdate
//        self.fumbleOnlyOnFirstDie = fumbleOnlyOnFirstDie
//        self.fumbleValues = fumbleValues
//        self.modifier = modifier
//        self.percentDice = percentDice
//        self.reorderDice = reorderDice
//        self.rerollOptions = rerollOptions
//        self.sumUp = sumUp
//    }
//    
//    public var uuid: UUID?
//    var name: String?
//    var information: String?
//    var diceCategory: String = ""
//    var tags: String?
//    var displayState: Int32 = 0
//
//    var addDiceEvery: Int16 = 0
//    var compareOption: Int16 = 0
//    var compareValue: Float = 0.0
//    var coupOnlyOnFirstDie: Bool = false
//    var coupValues: String = ""
//    var dice: String?
//    var diceUpdate: String = ""
//    var fumbleOnlyOnFirstDie: Bool = false
//    var fumbleValues: String = ""
//    var modifier: Float = 0.0
//    var percentDice: Bool = false
//    var reorderDice: Bool = false
//    var rerollOptions: String = ""
//    var sumUp: Bool = true
//}
