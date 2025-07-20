import AppIntents
import RolePlayGameKit
import PhotoRPG

struct MyAppPackage: AppIntentsPackage {
   static var includedPackages: [any AppIntentsPackage.Type] {
       [RPGFrameworkPackage.self, PhotoFrameworkPackage.self]
   }
}
