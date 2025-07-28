// @copyright André Trettin

import AppIntents
import RolePlayGameKit
import AudioRPG
import PdfRPG
import PhotoRPG
import SpaceRPG

struct MyAppPackage: AppIntentsPackage {
   static var includedPackages: [any AppIntentsPackage.Type] {
       [
        RPGFrameworkPackage.self,
        AudioFrameworkPackage.self,
        PdfFrameworkPackage.self,
        PhotoFrameworkPackage.self,
        SpaceFrameworkPackage.self,
       ]
   }
}
