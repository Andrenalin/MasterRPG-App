// @copyright André Trettin

#if !os(tvOS)
import AppIntents
import CoreRPG
import RolePlayGameKit
import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import GameRPG
import GeneratorRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RuleRPG
import SpaceRPG
import TableRPG
import WeatherRPG

struct MyAppPackage: AppIntentsPackage {
   static var includedPackages: [any AppIntentsPackage.Type] {
       [
        RPGFrameworkPackage.self,
        CoreFrameworkPackage.self,
        AdventureFrameworkPackage.self,
        AudioFrameworkPackage.self,
        CharacterFrameworkPackage.self,
        DiceFrameworkPackage.self,
        GameFrameworkPackage.self,
        GeneratorFrameworkPackage.self,
        MapFrameworkPackage.self,
        PdfFrameworkPackage.self,
        PhotoFrameworkPackage.self,
        RuleFrameworkPackage.self,
        SpaceFrameworkPackage.self,
        TableFrameworkPackage.self,
        WeatherFrameworkPackage.self,
       ]
   }
}

#endif
