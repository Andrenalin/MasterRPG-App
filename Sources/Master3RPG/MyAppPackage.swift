// @copyright André Trettin

import AppIntents
import RolePlayGameKit
import AudioRPG
import DiceRPG
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
        DiceFrameworkPackage.self,
        PdfFrameworkPackage.self,
        PhotoFrameworkPackage.self,
        SpaceFrameworkPackage.self,
        TableFrameworkPackage.self,
        WeatherFrameworkPackage.self,
       ]
   }
}
