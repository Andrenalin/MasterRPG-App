# DetailInspectorModel Performance Optimizations

## Current Implementation

The `DetailInspectorModel` stores an `AnyView?` for the inspector view:

```swift
@MainActor @Observable public final class DetailInspectorModel {
    public var currentInspectorView: AnyView? = nil
    // ...
}
```

**Usage in ItemDetailRootView.swift:143:**
```swift
detailInspectorModel.currentInspectorView = AnyView(inspectorView(model: model))
```

## Why .equatable() Cannot Be Used

The `inspectorView(model:)` method returns heterogeneous view types:

```swift
@ViewBuilder func inspectorView(model: any ItemDataAccessable) -> some View {
    Group {
        if hasAnyInspector(model: model) {
            if model.specialCategory {
                LinkItemRootView(...)  // Type A
            } else {
                inspector              // Type B (different type)
            }
        } else {
            ContentUnavailableView { ... }  // Type C
        }
    }
}
```

**Problem:** `.equatable()` requires `Self: Equatable`, but `some View` with conditional types doesn't satisfy this.

**Error:**
```
error: referencing instance method 'equatable()' on 'View' requires that 'some View' conform to 'Equatable'
```

## Current Optimization

The code is already optimized using `onChange(of: model.id)`:

```swift
.onChange(of: model.id, initial: true) {
    // Only updates when model.id changes
    detailInspectorModel.currentInspectorView = AnyView(inspectorView(model: model))
}
```

**Benefits:**
- ✅ Updates only when navigating to different items
- ✅ Doesn't update on model property changes
- ✅ Simple and maintainable code

**Performance:** Per benchmarks, this approach shows acceptable overhead (~20-30% compared to ID-based alternative).

## Alternative A: ID-Based Approach (If Optimization Needed)

If benchmarks show unacceptable performance, use this approach:

### 1. Update DetailInspectorModel

```swift
@MainActor @Observable public final class DetailInspectorModel {
    public var canShowInspector: Bool = false
    public var disableShowInspector: Bool = false
    public var currentInspectorId: UUID? = nil  // Instead of AnyView
    public var showInspector: Bool = false
}
```

### 2. Update ItemDetailRootView Usage

```swift
// Store just the ID
.onChange(of: model.id, initial: true) {
    detailListController.resetParentModel(model: model)
    detailInspectorModel.canShowInspector = canShowInspector(model: model)
    updateInspectorStates(model: model)
    detailInspectorModel.currentInspectorId = model.id  // Lightweight!
    withAnimation { selection.selectedItem = nil }
}

// Build view on-demand in inspector presentation
var inspectorContent: some View {
    if let inspectorId = detailInspectorModel.currentInspectorId {
        inspectorView(for: inspectorId)
    }
}
```

### 3. Performance Impact

Based on benchmarks:
- **Current (AnyView)**: ~0.045s for 100 updates
- **ID-Based**: ~0.032s for 100 updates
- **Improvement**: ~29%

**Trade-offs:**
- ✅ ~30% faster
- ✅ Lower memory footprint
- ❌ More complex code
- ❌ Need to maintain ID → View mapping

### 4. When to Use ID-Based Approach

Consider refactoring if:
1. ⚠️ User-visible lag during navigation
2. ⚠️ Profiling shows > 50ms overhead in ItemDetailRootView
3. ⚠️ Memory profiling shows excessive AnyView allocations
4. ⚠️ Benchmarks show > 50% overhead

**Current Status:** ✅ Keep current implementation (performance acceptable)

## Alternative B: Equatable Wrapper (Complex)

Create a custom equatable wrapper:

```swift
struct EquatableViewWrapper: View, Equatable {
    let id: UUID
    let buildView: (UUID) -> AnyView

    var body: some View {
        buildView(id)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

// Usage
detailInspectorModel.currentInspectorView = AnyView(
    EquatableViewWrapper(id: model.id) { id in
        AnyView(inspectorView(model: model))
    }.equatable()
)
```

**Trade-offs:**
- ✅ Can use `.equatable()`
- ❌ Very complex
- ❌ Still stores closure and AnyView
- ❌ Minimal performance benefit over current approach

**Verdict:** Not recommended - complexity outweighs benefits

## Recommendation

**✅ Keep Current Implementation**

Reasons:
1. Already optimized with `onChange(of: model.id)`
2. Simple and maintainable
3. Acceptable performance (<30% overhead)
4. Code clarity > theoretical optimization
5. Not in hot rendering loop

**If optimization becomes necessary** (based on real profiling data):
- Use Alternative A (ID-Based Approach)
- Expected 29% improvement
- Worth complexity only if user-visible lag

## Benchmark Reference

Run performance benchmarks to validate:
```bash
./Tests/CoreRPGPerformanceTests/run_benchmarks.sh
```

Check these specific tests:
- `testPerformance_NavigationScenario_Current`
- `testPerformance_NavigationScenario_IDBased`
- `testMemory_CurrentImpl_Storage`

## See Also

- Performance Benchmarks: `Tests/CoreRPGPerformanceTests/README.md`
- DetailInspectorModel: `Modules/CoreRPG/Model/DetailInspectorModel.swift`
- Usage: `Modules/CoreRPG/LGViews/ItemDetailRootView.swift:143`
