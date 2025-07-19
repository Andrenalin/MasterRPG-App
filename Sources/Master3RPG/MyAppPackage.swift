import AppIntents
import RolePlayGameKit

struct MyAppPackage: AppIntentsPackage {
   static var includedPackages: [any AppIntentsPackage.Type] {
       [RPGFrameworkPackage.self]
   }
}
