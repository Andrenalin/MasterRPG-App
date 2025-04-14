import Foundation

public final class Resources {

    public static let bundle = Bundle(for: Resources.self)

    public static let exampleFirstData = "ExampleData"
    public static let exampleFirstGermanData = "ExampleData-Deutsch"
    
    public enum Dice: String {
        case d20_1 = "D20_1"
        case d20_2 = "D20_2"
        case d20_3 = "D20_3"
        case d20_4 = "D20_4"
        case d20_5 = "D20_5"
        case d20_6 = "D20_6"
        case d20_7 = "D20_7"
        case d20_8 = "D20_8"
        case d20_9 = "D20_9"
        case TwoD20_1 = "2D20_1"
        case TwoD20_2 = "2D20_2"
        case TwoD20_3 = "2D20_3"
        case TwoD20_4 = "2D20_4"
        case TwoD20_5 = "2D20_5"
        case TwoD20_6 = "2D20_6"
    }
}
