# PDF tag extraction eval: work state

Status 2026-11-28: **in progress**. The combined change is committed on branch
`pdf-tag-eval-combined` (not merged into `develop`). Goal: raise the pass rate of
`PdfTagEvaluationTests` to at least 95% with no regressions on passing fixtures.

| | Runs passed | Fixtures passed (≥4/5 runs) |
|---|---|---|
| Baseline (`develop` 0790fdaeb) | 56/75 = 74.7% | 11/15 |
| Combined (this branch) | **62/75 = 82.7%** | 11/15 |
| Target | ≥72/75 = 95% | |

Remaining steps of the original task:
1. One more iteration on the open failure causes below (category bias, kind word from the
   title; decide on a guardrail retry).
2. Add fixtures for the real-world failure patterns found (see "New fixture ideas").
3. Build all platforms (only iOS and macOS were built so far) and run the full unit plan.
4. Write `EVAL_REPORT.md` (baseline vs. final, each change and its effect, remaining
   failures, untried ideas). This file has most of its content.

## How to run

```bash
TEST_RUNNER_PDF_TAG_EVAL=1 xcodebuild test -workspace MasterRPG.xcworkspace -scheme MasterRPG \
  -testPlan MasterRPG -destination 'platform=iOS Simulator,id=<iPhone 18 Pro on iOS 27.2>' \
  -only-testing:GeneratorRPGTests/PdfTagEvaluationTests
```

- ~18 min for 15 fixtures × 5 runs. `TEST_RUNNER_PDF_TAG_EVAL_RUNS=2` for a quick check.
- Only one eval may use the on-device model at a time (several in parallel time out).
  Parallel worktrees can build at the same time, but the eval runs must be serialized
  (a `lockf` wrapper around `test-without-building` worked well).
- Read the result from the `PDF tagging: <fixture> - n/5 runs passed` lines in the log.
- **Noise:** with an unchanged prompt the result moves by about ±3 runs between evals
  (Science fiction rulebook got "Rulebook" in 0/5 runs at baseline, 3/5 in another
  unchanged-input run). A ±1 fixture difference is not a signal.
- **Guardrail errors** ("Content policy prevented analysis" / "safety guardrails were
  triggered") hit the Gothic horror fixture in some evals, also with input byte-identical to
  the baseline. The baseline had none. They count as failed runs.

GeneratorRPG unit tests on macOS: `MasterMac` has no test action. Copy a scheme with only the
`GeneratorRPGTests` testable (target id `599DCAD72E8E30C00056E46C`, hostless, supports
macOS), run it with `-destination 'platform=macOS,arch=arm64'`, delete the scheme afterwards.

## Baseline failures (19 failing runs)

| Cause | Fixtures | Failing runs |
|---|---|---|
| No tag says what kind of document it is ("Fantasy", "Erlebnis", "Game", "Regelwerk" instead of adventure, inn, rulebook, character sheet) | Wurzelnest, Feinschmecker, Botho, Starlane | 4 + 4 + 3 + 5 |
| A tag repeats the title ("Wurzelnest", "Feinschmecker") | Wurzelnest, Feinschmecker | 5 + 1 |
| Generic tag ("Rollenspiel", "Role-playing game", "Game") | Gammaslayers, Starlane | 1 + 5 |
| No genre tag (no sci-fi) | Starlane | 5 |
| Noisy input (`￼` lines and number grids on a character sheet; imprint and license pages first) | Botho, Gammaslayers, Regeln von Caera | risk |

## Hypotheses tested (one worktree each, full 5-run eval)

| | Change | Runs | Fixtures | Kept? |
|---|---|---|---|---|
| A, input formatting | `PdfAnalysisTextCleaner`: strip U+FFFC / soft hyphens / zero-width chars, drop letterless lines (number grids), collapse whitespace and dot leaders, rejoin line-break hyphens, skip imprint/credits/license pages | 54/75 | 11/15 | **yes**: Botho 2→5/5, Gammaslayers 4→5/5; the dip came from 3 guardrail errors on unchanged generated input |
| B, document metadata | File name, PDF title/subject/keywords and outline labels as a fenced "Document details" block | 51/75 | 10/15 | **no**: the test PDFs carry almost no metadata, so it was only the file name; it pulled tags toward the name (Caera 5→2/5, Botho lost "Horror") |
| C, rules in code | `GeneratedTagRules.cleaned(_:title:)` drops title repeats, generic tags (EN/DE) and banned-word tags; asked for spare candidates | 56/75 | 10/15 | **yes**: removes those violations for good, but cannot add a missing concept. Forcing 7 candidates overflowed the context on the Brigands PDF |
| D, kind and genre fields | `@Generable enum` category, then `documentKind` and `genre` strings generated before the free tags | 58/75 | 10/15 | **yes, with fixes**: the kind tag became reliable ("Gasthaus" every run). Its second wording ("never copy the English category value") made English worse ("protocol" instead of "rulebook"); the model also copied "characterSheet" |

## The combined change (this branch)

- `PdfAnalysisTextCleaner` (new) + `PdfPageTextReader.pages(…, cleansForAnalysis:)`: A as tested.
  Other `PdfPageTextReader` callers keep the default `false`.
- `GeneratedTagRules.cleaned(_:title:)`, `everyDocumentTags`, `bannedWordForms`,
  `comparisonKey`: C, without the spare-candidate count. The old `cleaned(_:)` is unchanged
  (photo, table, character keep their behavior).
- `PdfSummaryAnalysis`: after `title`/`summary` come `category: PdfDocumentCategory`,
  `documentKind`, `genre`, then 3–4 free `tags` (one spare). The stored tags are built by
  `PdfSummaryAnalysis.tags(category:documentKind:genre:tags:title:outputLanguage:)`:
  kind, genre, free tags, then `cleaned(_:title:)`, max 5.
- `kindTag(…)` keeps the model's own kind word ("Stadtbeschreibung", "Gasthaus") unless it is
  empty, a copied category value, camel case, generic, longer than 3 words, or the title or
  genre again. Then it uses `PdfDocumentCategory.name(in:)`, a fixed word per output language
  (same language list as `MapPlaceKind`). While streaming there is no output language, so an
  unusable kind is left out until the result replaces it.
- D's first-round `documentKind` wording, not its second.
- Tests: `PdfAnalysisTextCleanerTests`, `GeneratedTagRulesTests` (title/generic/banned
  filtering), `PdfSummaryTagsTests` (kind fallback, order, cap, names for every language).
  All 271 GeneratorRPG tests pass on iOS and macOS.

### Combined result per fixture

| Fixture | Baseline | Combined | Tags / failure |
|---|---|---|---|
| Fantasy dungeon adventure | 5/5 | 5/5 | dungeoncrawl, fantasy, crypt, Greywater, Ash King |
| Science fiction rulebook | 0/5 | **0/5** | kind "Adventure" (3) or "protocol" (2); genre "space"/"science fiction" now present; no rulebook and no dice/skill/combat concept |
| Gothic horror investigation | 5/5 | 3/5 | 2 guardrail errors; passing runs: scenario, gothic horror, investigation, Blackmoor Fen, cult |
| German fantasy adventure | 5/5 | 5/5 | Abenteuer, Fantasy, Burg, Eschenau, Geist |
| Angriff auf das Wurzelnest | 0/5 | 2/5 | always "Abenteuer", no title repeat; 3 runs miss rats/cult/bones (free tags go to Vestrach, Kobolde, Lebendige Wurzel) |
| Botho Phillip zu Eulenburg | 2/5 | 3/5 | 2 runs give kind "Abenteuer" for a character sheet |
| Brigands of Lyrkenfenn | 5/5 | 5/5 | dungeon, (dark) fantasy, marsh, brigands, ruins |
| Caera Krautwerk | 5/5 | 5/5 | Regelwerk, Fantasy, Kräuter, Aensenflieh, Heilung |
| Der Rostige Schüssel | 5/5 | 5/5 | Abenteuer, postapokalypse, Schrottplatz, Mutanten, Strahlung |
| Die Räuber von Lyrkenfenn | 5/5 | 5/5 | Dungeon, Fantasy, Sumpf, Räuber, Turmruine |
| Gammaslayers | 4/5 | 5/5 | Regelwerk, Postapokalypse, Überlebende, Ruinenstädte, Mutation |
| Regeln von Caera | 5/5 | 5/5 | Regelwerk, Fantasy, Charaktererschaffung, … |
| Sturmelfen | 5/5 | 5/5 | story/Geschichte, Fantasy, Sturmelfen, Insel, Magie |
| Valen Coladris | 5/5 | 4/5 | one run's kind "citymap" (English word in German output, forbidden term "city") |
| Zum blauen Wunder (inn) | 0/5 | **5/5** | Gasthaus, Fantasy, Speisen, Wyndland, Kreaturen |

## Open failure causes and next ideas

1. **Category leans toward "adventure"** (Starlane 3, Botho 2): "adventure" is the first case
   of `PdfDocumentCategory`, so the model may default to it. Try: put a neutral case first or
   reorder; log the generated `category` in the eval report (it is not printed today) so the
   category itself can be judged.
2. **Kind word taken from the title** ("protocol" from "Starlane Protocol"): `kindTag` only
   rejects the whole title. Also reject a kind word that is a word of the title (the fixed
   category word replaces it).
3. **English kind in German output** ("citymap", "story"): `kindTag` could reject a lowercase
   kind word for German output, or one that matches the English category names when the
   output language is not English.
4. **Guardrail errors** (Gothic horror 2): retrying once in `PdfSummaryAnalyzer` when the
   guardrail fires would remove most of them. It changes runtime behavior, not the prompt, so
   ask first.
5. **Content concept misses** (Wurzelnest rats/cult): the model prefers the kobolds. No clear
   idea yet. Don't widen fixture concept lists to chase synonyms.

Even with 1–4 fixed, about 68–70/75 is realistic; reaching 95% may need more runs per fixture
to tell signal from noise.

## New fixture ideas (task step 5, not done yet)

Generated fixtures for the patterns found, so they stay covered:
- a character sheet with number grids and `￼`-like noise (Botho pattern: kind must be a
  character sheet, not "Abenteuer"/"Regelwerk");
- an inn/tavern description with a menu table (Feinschmecker pattern: inn + food);
- a book whose first pages are imprint and license text (Gammaslayers pattern);
- a short title word that tempts a title-repeat tag (Wurzelnest pattern);
- an English core rulebook whose title contains a non-kind word ("… Protocol").

## Untried ideas

- Trim the `sections` output for long PDFs to free context (Brigands is near the limit).
- Map the category to a fixed word always for English and German and use the model's word
  only for other languages (simpler, but loses exact words like "Stadtbeschreibung").
- A second, tags-only generation pass with the summary as input.
- Reporting guardrail errors separately from tag failures in `PdfTagEvaluationTests`.

## Leftovers outside this branch

- The four hypothesis worktrees (`.claude/worktrees/agent-*`, branches `worktree-agent-*`)
  still hold their uncommitted changes; B's metadata context (`PdfDocumentContext`) exists
  only there. Delete them with `git worktree remove` when no longer needed.
- Eval logs were written to a session scratchpad and are not kept; the per-fixture results
  above are the record.
