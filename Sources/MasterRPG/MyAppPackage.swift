// @copyright André Trettin

#if !os(tvOS)
import AppIntents
import RoleGameKit
import RPGAdventures
import AudioRPG
import RPGValues
import DiceRPG
import RPGMaps
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

struct MyAppPackage: AppIntentsPackage {
   static var includedPackages: [any AppIntentsPackage.Type] {
       [
        RPGFrameworkPackage.self,
//        AdventureFrameworkPackage.self,
        AudioFrameworkPackage.self,
        CharacterFrameworkPackage.self,
        DiceFrameworkPackage.self,
//        GeneratorFrameworkPackage.self,
//        MapFrameworkPackage.self,
        PdfFrameworkPackage.self,
        PhotoFrameworkPackage.self,
        SpaceFrameworkPackage.self,
        TableFrameworkPackage.self,
        WeatherFrameworkPackage.self,
       ]
   }
}

#endif
