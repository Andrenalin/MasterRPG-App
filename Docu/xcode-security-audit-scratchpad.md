# Xcode Security Audit Scratchpad

## Audit Table

| Target | ENABLE_ENHANCED_SECURITY | setAtTargetLevel | ENABLE_HARDENED_RUNTIME | SDKROOT | SUPPORTED_PLATFORMS |
|--------|--------------------------|-----------------|------------------------|---------|---------------------|
| MasterRPG | NO | no | YES (target) | auto (iphoneos/sim) | iphoneos iphonesimulator xros xrsimulator |
| MasterTV | NO | no | NO | appletvos | appletvos appletvsimulator |
| MasterMac | NO | no | YES (target) | macosx | macosx |
| DiceRollerWidgetExtension | NO | no | YES (target) | auto (iphoneos/sim) | iphoneos iphonesimulator xros xrsimulator |
| RPGShare | NO | no | NO | iphoneos | iphoneos iphonesimulator macosx xros xrsimulator |

### Languages
- Swift: YES (2660+ files)
- C: Only in SPM dependencies (swift-syntax) — not project source
- Objective-C: NO
- C++: NO
- Objective-C++: NO

**Project is pure Swift.**

### Basic Clang Safety Warning Status (pure Swift — not applicable)
- GCC_WARN_ABOUT_RETURN_TYPE: YES_ERROR (all targets, already hardened)
- GCC_WARN_UNINITIALIZED_AUTOS: YES_AGGRESSIVE (all targets, already hardened)
- GCC_WARN_64_TO_32_BIT_CONVERSION: YES (all targets, already hardened)
- CLANG_WARN_IMPLICIT_FALLTHROUGH: NO (all targets — but not applicable to Swift)
- GCC_TREAT_IMPLICIT_FUNCTION_DECLARATIONS_AS_ERRORS: NO (not applicable, no C/ObjC)
- CLANG_ANALYZER_SECURITY_FLOATLOOPCOUNTER: NO (not applicable, no C/ObjC)
- CLANG_ANALYZER_SECURITY_INSECUREAPI_RAND: NO (not applicable, no C/ObjC)
- CLANG_ANALYZER_SECURITY_INSECUREAPI_STRCPY: NO (not applicable, no C/ObjC)

### Deliberately Disabled Settings
None found. No security-relevant build settings have an explicit targetValue of NO.

### Entitlement Concerns
MasterRPG.entitlements (shared by MasterRPG and MasterMac):
- com.apple.security.cs.allow-jit = true ← weakens macOS Hardened Runtime
- com.apple.security.cs.allow-unsigned-executable-memory = true ← weakens macOS Hardened Runtime

These macOS Hardened Runtime exception entitlements are present in the shared entitlements file. On iOS/visionOS they are ignored, but on macOS (MasterMac) they reduce the app's security posture and should be investigated.

## Enhanced-Security Buckets

| Target | Product Type | Bucket | Notes |
|--------|-------------|--------|-------|
| MasterRPG | Application (mh_execute, .app) | Off | Platforms: iphoneos/xros — arm64e supported |
| MasterTV | Application (mh_execute, .app) | Off | Platform: appletvos — arm64e supported on Apple TV 4K 3rd gen+ |
| MasterMac | Application (mh_execute, .app) | Off | Platform: macosx — arm64e supported on Apple Silicon |
| DiceRollerWidgetExtension | App extension (.appex) | Skipped | |
| RPGShare | App extension (.appex) | Skipped | |

### Hardware Memory Tagging eligible targets
- MasterRPG: iphoneos iphonesimulator xros xrsimulator → qualifies
- MasterMac: macosx → qualifies
- MasterTV: appletvos only → does not qualify (tvOS not in supported list)

## Version Control
Project is git-tracked (from environment context).
