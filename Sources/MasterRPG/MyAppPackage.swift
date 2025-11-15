// @copyright André Trettin

#if !os(tvOS)
import AppIntents
import RoleGameKit
import RPGAdventures
import RPGAudios
import RPGValues
import RPGDie
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGWeathers

struct MyAppPackage: AppIntentsPackage {
   static var includedPackages: [any AppIntentsPackage.Type] {
       [
        RPGFrameworkPackage.self,
//        AdventureFrameworkPackage.self,
        AudioFrameworkPackage.self,
//        CharacterFrameworkPackage.self,
        DiceFrameworkPackage.self,
//        MapFrameworkPackage.self,
        PdfFrameworkPackage.self,
        PhotoFrameworkPackage.self,
        SpaceFrameworkPackage.self,
//        TableFrameworkPackage.self,
        WeatherFrameworkPackage.self,
       ]
   }
}

#endif
