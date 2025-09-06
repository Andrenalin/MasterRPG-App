// @copyright André Trettin

import AppIntents
import RolePlayGameKit
import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

struct MyAppPackage: AppIntentsPackage {
   static var includedPackages: [any AppIntentsPackage.Type] {
       [
        RPGFrameworkPackage.self,
        AudioFrameworkPackage.self,
        CharacterFrameworkPackage.self,
        DiceFrameworkPackage.self,
        MapFrameworkPackage.self,
        PdfFrameworkPackage.self,
        PhotoFrameworkPackage.self,
        SpaceFrameworkPackage.self,
        TableFrameworkPackage.self,
        WeatherFrameworkPackage.self,
       ]
   }
}
