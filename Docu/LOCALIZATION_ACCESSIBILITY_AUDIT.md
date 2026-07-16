# Localization and Accessibility Verification

Run both repository gates before submitting UI changes:

```bash
ruby Scripts/verify_localization.rb
ruby Scripts/verify_accessibility.rb
```

## Localization gate

`verify_localization.rb` scans production Swift under `Modules/` and `Sources/`
and every String Catalog under `Modules/`, `Sources/`, and `Resources/`. It
requires:

- framework UI literals and localization APIs to use `bundle: .module`;
- executable, extension, and widget UI literals to use `bundle: .main`;
- data-only text to use `Text(verbatim:)` or a typed `Text(_:format:)`;
- every statically discoverable localized key to be active in its target
  catalog;
- every active catalog entry to have a complete German translation;
- source and German placeholders to match; and
- catalogs to contain no stale entries after compiler extraction.

App Intent metadata is the deliberate exception to explicit bundle injection.
Xcode's metadata exporter requires direct literal resources for intent titles,
parameter titles, summaries, and dialogs. Runtime UI strings in intent results
still use the module bundle.

Use a clean Xcode build with `SWIFT_EMIT_LOC_STRINGS=YES` to reconcile compiler
extraction before relying on the catalog-only result.

## Accessibility gate

`verify_accessibility.rb` masks comments and previews, then audits all
production Swift sources for:

- fixed text sizes that bypass Dynamic Type;
- disallowed `fontWeight` usage;
- simple tap gestures that should be semantic buttons;
- continuous animation that ignores Reduce Motion;
- animation timelines that do not pause for Reduce Motion;
- sliders without localized labels; and
- invisible content that remains hit-testable or exposed to accessibility.

The only fixed-font exception is `AnimatableFont.swift`, whose public purpose is
to interpolate an explicit font size. Preview-only demonstration sizing is
masked from the production audit.

The source gate complements, rather than replaces, manual review. Reviewers
must still verify meaningful image labels, icon-only button names and hit
targets, selected/disabled values, aggregate semantics for complex canvases,
contrast, Reduce Motion, and Dim Flashing Lights behavior in affected views.
