# Xcode Security Settings Decisions

**Project:** MasterRPG
**Last updated:** 2026-07-17

This document records the security build setting and entitlement decisions for MasterRPG.

---

## Build Settings

### ENABLE_ENHANCED_SECURITY

| Target | Status | Notes |
|--------|--------|-------|
| MasterRPG | **Enabled** (2026-07-17) | Applied `ENABLE_ENHANCED_SECURITY = YES`. Activates pointer authentication (arm64e), stack variable zeroing, and security compiler warnings. Platforms: iphoneos, xros. |
| MasterTV | **Enabled** (2026-07-17) | Applied `ENABLE_ENHANCED_SECURITY = YES`. Platforms: appletvos. |
| MasterMac | **Enabled** (2026-07-17) | Applied `ENABLE_ENHANCED_SECURITY = YES`. Platform: macosx. |
| DiceRollerWidgetExtension | **Skipped** | App extension — not a supported product type for Enhanced Security entitlements. |
| RPGShare | **Skipped** | App extension — not a supported product type for Enhanced Security entitlements. |

### Basic Clang Safety Warnings

**Omitted.** The project is pure Swift — no C, Objective-C, or C++ source files are present. Clang-specific warnings are not applicable.

The following are already correctly set for any C/ObjC code that may be added in future:
- `GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR` ✓
- `GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE` ✓
- `GCC_WARN_64_TO_32_BIT_CONVERSION = YES` ✓

### Hardware Memory Tagging

**Deferred.** Eligible targets: MasterRPG (iphoneos/xros), MasterMac (macosx). Requires M5-class Apple silicon hardware support. Can be enabled later by checking this item in a new audit plan.

### Bounds Safety Adoption

**Not applicable.** No C or C++ source files in the project.

---

## Entitlements

### MasterRPG.entitlements (shared by MasterRPG and MasterMac)

| Entitlement | Action | Rationale |
|-------------|--------|-----------|
| `com.apple.security.cs.allow-jit` | **Removed** (2026-07-17) | This macOS Hardened Runtime exception grants the app permission to create writable executable memory (JIT). No feature in MasterRPG requires JIT compilation — this was likely a template leftover and weakened macOS security for MasterMac. |
| `com.apple.security.cs.allow-unsigned-executable-memory` | **Removed** (2026-07-17) | This exception allows the app to map unsigned executable memory pages, bypassing code signing for runtime-loaded code. No feature in MasterRPG requires this — removing it restores macOS Hardened Runtime integrity for MasterMac. |

---

## Notes

- `com.apple.developer.aps-environment` and `aps-environment` both appear in MasterRPG.entitlements. The former is the modern key; `aps-environment` is the legacy key. Both are harmless but `aps-environment` can be removed if desired (not a security issue).
- MasterTV does not have `ENABLE_HARDENED_RUNTIME = YES` — this is expected for tvOS apps (Hardened Runtime is a macOS concept).
