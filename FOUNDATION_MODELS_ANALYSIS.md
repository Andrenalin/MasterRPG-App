# Foundation Models Usage Analysis: GeneratorRPG Module

**Date:** 2026-03-24
**Module:** `Modules/GeneratorRPG/`
**Framework:** Apple's FoundationModels (Apple Intelligence)

---

## Executive Summary

The GeneratorRPG module integrates Apple's **FoundationModels** framework to provide AI-powered content generation for tabletop RPG game masters. The implementation uses:

- **SystemLanguageModel** for on-device AI inference
- **Structured generation** with `@Generable` macro for type-safe AI outputs
- **Streaming responses** for real-time content generation
- **Language/availability checks** to ensure Apple Intelligence compatibility

**Primary Use Cases:**
1. **Adventure Generation** - Creating campaigns, scenarios, and quests
2. **Character Generation** - Building NPCs with attributes and backgrounds
3. **Content Extraction** - Parsing unstructured RPG text into structured data
4. **Interactive Chat** - Conversational assistant for game masters

---

## Architecture Overview

### Core Components

```
GeneratorRPG/
├── BasicAI/                    # Foundation model infrastructure
│   ├── FoundationManager.swift      # Availability & language checking
│   ├── FoundationBasicView.swift    # UI wrapper with checks
│   ├── CheckLanguageSupport.swift   # Locale validation UI
│   └── IntelligenceUnavailableView.swift
├── Controller/
│   ├── AdventureGeneratorController.swift  # Adventure/chat generation
│   └── GeneratorController.swift           # Multi-purpose generator
├── Model/                      # @Generable data models
│   ├── AdventureGenModel.swift    # Campaign/Adventure/Scenario
│   ├── CharacterGenModel.swift    # Character attributes
│   ├── BlockGenModel.swift        # Content extraction blocks
│   └── TableGenModel.swift        # (referenced but not examined)
└── Playground/
    └── MyAiPlayground.swift       # Testing/experimentation
```

---

## Foundation Models Integration Details

### 1. **FoundationManager** - System Check & Availability

**File:** `BasicAI/FoundationManager.swift`

**Purpose:** Central coordinator for Apple Intelligence availability

```swift
@Observable
final class FoundationManager {
    var isModelAvailable: Bool = false
    var isLanguageSupported = false
    private(set) var notAvailableReason: LocalizedStringKey

    func checkIsAvailable() -> Bool {
        switch SystemLanguageModel.default.availability {
        case .available:
            isModelAvailable = true
        case .unavailable(.deviceNotEligible):
            // Device doesn't support Apple Intelligence
        case .unavailable(.appleIntelligenceNotEnabled):
            // User hasn't enabled in Settings
        case .unavailable(.modelNotReady):
            // Model downloading or temporarily unavailable
        }
    }
}
```

**Key Features:**
- Checks `SystemLanguageModel.default.availability`
- Provides user-friendly error messages
- Validates locale support via `supportsLocale()`
- Helper method `minimizeMarkDown()` for cleaning AI output

**Usage Pattern:**
```swift
FoundationBasicView {
    // Your AI-powered UI
}
```

This wrapper automatically checks availability and shows appropriate UI:
- Apple Intelligence available → Show content
- Language not supported → Show language warning + content
- Not available → Show `IntelligenceUnavailableView`

---

### 2. **Structured Generation with @Generable**

The module heavily uses the `@Generable` macro for type-safe AI output.

#### **CharacterGenModel** - Hierarchical Character Data

**File:** `Model/CharacterGenModel.swift`

```swift
@Generable(description: "The character description")
struct CharacterGenModel: Equatable, Hashable, Codable, Sendable {
    @Guide(description: "The name of the character or the group of values")
    var name: String

    @Guide(description: "A description about the character or the group")
    var information: String

    @Guide(description: "A tag description", .maximumCount(5))
    var tags: [String]

    @Guide(description: "A character has many named values like key value pairs")
    var entries: [CharacterEntryGenModel] = []
}

@Generable
struct CharacterEntryGenModel: Equatable, Hashable, Codable, Sendable {
    @Guide(description: "The name is the title of the value")
    var name: String

    @Guide(description: "The content is the value for the character")
    var content: String

    @Guide(description: "The value type of content")
    var valueType: ValueType

    @Guide(description: "A folder of values", .maximumCount(1))
    var groupedValues: [CharacterGenModel]  // Recursive structure

    @Generable(description: "The type of the content.")
    enum ValueType: Int {
        case text, number, decimal, selection
    }
}
```

**Design Highlights:**
- **Recursive structure**: Characters can contain nested character groups
- **Type safety**: `ValueType` enum guides AI to generate appropriate data types
- **Constraints**: `@Guide(.maximumCount(5))` prevents excessive outputs
- **Sendable conformance**: Safe for concurrent access

#### **AdventureGenModel** - Nested Campaign Structure

**File:** `Model/AdventureGenModel.swift`

```swift
@Generable
struct CampaignGenModel: Equatable {
    @Guide(description: "An exciting name for the campaign.")
    var name: String
    var description: String
    @Guide(description: "Tags to describe the campaign.", .maximumCount(4))
    var tags: [String]
    @Guide(description: "The collection of adventure.", .maximumCount(5))
    var entries: [AdventureGenModel]
}

@Generable
struct AdventureGenModel: Equatable {
    var name: String
    var description: String
    var tags: [String]
    @Guide(.minimumCount(5))  // Ensure at least 5 scenarios
    var entries: [ScenarioGenModel]
}

@Generable
struct ScenarioGenModel: Equatable {
    var name: String
    var description: String
    var tags: [String]
    @Guide(.minimumCount(10))  // At least 10 entries per scenario
    var entries: [EntryGenModel]
}
```

**Three-Level Hierarchy:**
1. **Campaign** → Collection of adventures (max 5)
2. **Adventure** → Collection of scenarios (min 5)
3. **Scenario** → Collection of entries (min 10)

**Constraints Strategy:**
- `.maximumCount()` prevents token exhaustion
- `.minimumCount()` ensures sufficient detail
- Descriptive `@Guide` text guides AI generation quality

#### **BlockGenModel** - Content Extraction

**File:** `Model/BlockGenModel.swift`

```swift
@Generable(description: "The block can be of four category: Adventure, Map, Character or Table.")
struct BlockGenModel: Equatable, Identifiable {
    let id: UUID = UUID()
    @Guide(description: "The name of this block.")
    let name: String
    @Guide(description: "More information about this block.")
    let information: String
    @Guide(description: "Tags to describe the content.")
    let tags: [String]
    @Guide(description: "The block is from Type Adventure, Map, Character or Table.")
    let blockCategory: BlockCategoryGenModel
    @Guide(description: "Each category has usually several smaller chunks.")
    var entries: [BlockEntryGenModel]
}

@Generable
enum BlockCategoryGenModel: String, CaseIterable {
    case adventure, map, character, table
}
```

**Purpose:** Parse unstructured RPG text (e.g., from PDFs) into categorized blocks

---

### 3. **Controllers** - Session Management & Generation

#### **AdventureGeneratorController** - Chat-Based Adventure Creation

**File:** `Controller/AdventureGeneratorController.swift`

```swift
@MainActor
final class AdventureSessionModel {
    var session = LanguageModelSession()
    var adventureChat: String?
    var extracted: [BlockEntryGenModel.PartiallyGenerated] = []
    var responseErrorContent: String = ""
}

struct AdventureGeneratorController: Sendable {
    let model: AdventureSessionModel
    let llm = SystemLanguageModel.default

    @MainActor func generate() {
        let session = LanguageModelSession {
            """
            You are an assistant to support a game master for creating a fictional game story.
            In the game you have NPC and players characters they have to talk to each other.
            Add connections to other possible outcomes or stories.
            Keep your answer precise except the game master needed a detailed version.
            """
        }
        model.set(session: session)
        session.prewarm()  // Pre-load model for faster first response
    }

    @MainActor func request(message: String) {
        Task {
            do {
                let prompt = Prompt { "\(message)" }
                let stream = model.session.streamResponse(to: prompt, options: GenerationOptions())

                for try await partialResponse in stream {
                    self.model.adventureChat = partialResponse.content
                }
            } catch let error as LanguageModelSession.GenerationError {
                // Comprehensive error handling
                switch error {
                case .guardrailViolation(let context):
                    model.responseErrorContent = "Guardrail Violation: ..."
                case .rateLimited(let context):
                    model.responseErrorContent = "Rate Limit exceeded: ..."
                case .exceededContextWindowSize(let context):
                    model.responseErrorContent = "Memory exceeded: ..."
                // ... more cases
                }
            }
        }
    }
}
```

**Key Features:**
- **System instructions** define AI personality/role
- **Streaming responses** via `streamResponse(to:options:)`
- **Prewarming** reduces first-response latency
- **Comprehensive error handling** for all FoundationModels error types

**Error Types Handled:**
- `.guardrailViolation` - Content policy violations
- `.rateLimited` - API throttling
- `.exceededContextWindowSize` - Token limit exceeded
- `.decodingFailure` - JSON parsing errors

#### **GeneratorController** - Multi-Purpose Generator

**File:** `Controller/GeneratorController.swift`

```swift
@MainActor
final class GeneratorSessionModel {
    var session = LanguageModelSession()
    var responses: [LanguageModelSession.ResponseStream<CharacterGenModel>.Snapshot] = []
    var result: CharacterGenModel?
    var characterChat: String?
    var campaign: CampaignGenModel.PartiallyGenerated?
    var extracted: BlockGenModel.PartiallyGenerated?
}

struct GeneratorController: Sendable {
    let model: GeneratorSessionModel
    let llm = SystemLanguageModel.default

    // 1. Generate character (unstructured)
    @MainActor func generate() {
        let session = LanguageModelSession {
            "You are an assistant to support a game master for a role play game."
        }
        model.set(session: session)
        session.prewarm()
    }

    @MainActor func request(message: String) {
        Task {
            let stream = model.session.streamResponse(options: GenerationOptions()) {
                "\(message)"
            }
            for try await partialResponse in stream {
                self.model.characterChat = partialResponse.content
            }
        }
    }

    // 2. Generate adventure (structured)
    @MainActor func requestAdventure(message: String) async {
        let prompt = Prompt { "\(message)" }
        let stream = model.session.streamResponse(to: prompt, generating: CampaignGenModel.self)

        for try await partialResponse in stream {
            self.model.campaign = partialResponse.content  // PartiallyGenerated type
        }
    }

    // 3. Extract content (structured)
    @MainActor func generateExtractor(from model: GeneratorModel) {
        let session = LanguageModelSession(instructions: """
            Your job is to identify the type of text, and split into
            Adventure, Map, Character or Table related text blocks.
            """)
        self.model.set(session: session)
        session.prewarm()
    }

    @MainActor func requestExtraction(message: String) async {
        let prompt = Prompt { "\(message)" }
        let stream = model.session.streamResponse(to: prompt, generating: BlockGenModel.self)

        for try await partialResponse in stream {
            self.model.extracted = partialResponse.content
        }
    }
}
```

**Three Generation Modes:**
1. **Unstructured text generation** - Free-form chat (`characterChat`)
2. **Structured adventure generation** - Type-safe `CampaignGenModel`
3. **Content extraction** - Parse unstructured text to `BlockGenModel`

**Important Pattern:**
```swift
// Unstructured
streamResponse(options:) { "prompt" }
// → Returns String content

// Structured
streamResponse(to:, generating: SomeModel.self)
// → Returns SomeModel.PartiallyGenerated
```

---

### 4. **Playground** - Experimental Features

**File:** `Playground/MyAiPlayground.swift`

```swift
#Playground("Chat with out structure") {
    let instructions = """
        You are an assistant to support the game master for a fantasy game.
        """
    let session = LanguageModelSession(instructions: instructions)

    let prompt = Prompt {
        "Give my some dwarven names and then names for pub where these dwarves could be."
    }

    let response = try await session.respond(to: prompt)
    print(response.content)
}

#Playground("Prompt Builder") {
    let instructions = """
        Your job is to identify the type of text, and split into
        Adventure, Map, Character or Table related text blocks.
        """
    let session = LanguageModelSession(instructions: instructions)

    let prompt = Prompt {
        """
        After meeting several obstacles in the marsh...
        1. GUARDROOM Two drunken brigands snore heavily...
        2. EMPTY ROOM There is an apple on the floor.
        ...
        """
    }

    // Test with default model
    let stream = session.streamResponse(to: prompt, generating: BlockGenModel.self)
    for try await partialResponse in stream {
        print(partialResponse.content)
    }

    // Test with contentTagging model
    let contentTaggingModel = SystemLanguageModel(useCase: .contentTagging)
    if contentTaggingModel.isAvailable {
        let session = LanguageModelSession(model: contentTaggingModel)
        let stream = session.streamResponse(to: prompt, generating: BlockGenModel.self)
        for try await newTags in stream {
            print(newTags.content)
        }
    }
}
```

**Experiments:**
1. **Unstructured prompt testing** - Quick validation of instructions
2. **Structured generation** - Test `@Generable` models
3. **Specialized models** - Try `SystemLanguageModel(useCase: .contentTagging)`

---

## Technical Patterns & Best Practices

### ✅ Good Practices Observed

1. **Comprehensive Availability Checking**
   ```swift
   switch SystemLanguageModel.default.availability {
   case .available: // ✓
   case .unavailable(.deviceNotEligible): // ✓
   case .unavailable(.appleIntelligenceNotEnabled): // ✓
   case .unavailable(.modelNotReady): // ✓
   }
   ```

2. **Streaming for Responsiveness**
   ```swift
   for try await partialResponse in stream {
       self.model.adventureChat = partialResponse.content
   }
   ```
   Updates UI in real-time as tokens arrive.

3. **Session Prewarming**
   ```swift
   session.prewarm()  // Pre-load model before first request
   ```

4. **Type-Safe Generation with @Generable**
   - Compile-time validation of model structure
   - `PartiallyGenerated` type for streaming
   - `@Guide` annotations improve output quality

5. **Proper Error Handling**
   - Catches specific `GenerationError` cases
   - Provides user-friendly error messages
   - Includes `failureReason` and `recoverySuggestion`

6. **@MainActor Isolation**
   - All session models are `@MainActor`
   - Controllers use `@MainActor func` where appropriate
   - UI updates are thread-safe

7. **Sendable Conformance**
   - Models conform to `Sendable` for concurrency safety
   - Controllers marked `Sendable` where possible

8. **Language Support Validation**
   ```swift
   SystemLanguageModel.default.supportsLocale(locale)
   ```

---

## Issues & Improvement Opportunities

### ❌ Critical Issues

#### 1. **Unstructured Task in Request Methods**

**Location:** `AdventureGeneratorController.swift:50`, `GeneratorController.swift:71`

**Problem:**
```swift
@MainActor func request(message: String) {
    Task {  // ❌ Unstructured task loses error context
        do {
            let stream = model.session.streamResponse(...)
            for try await partialResponse in stream { ... }
        } catch { ... }
    }
}
```

**Issues:**
- `Task` swallows errors - caller can't know if generation failed
- Fire-and-forget pattern - no way to await completion
- Error is set on model, but caller doesn't know when to check

**Fix:**
```swift
@MainActor func request(message: String) async throws {
    // Remove Task wrapper - let caller handle async
    do {
        let stream = model.session.streamResponse(...)
        for try await partialResponse in stream {
            self.model.adventureChat = partialResponse.content
        }
        model.responseErrorContent = ""  // Clear on success
    } catch let error as LanguageModelSession.GenerationError {
        // Handle and re-throw
        model.responseErrorContent = error.localizedDescription
        throw error
    }
}

// Usage:
Task {
    do {
        try await controller.request(message: userInput)
    } catch {
        // Show error UI
    }
}
```

#### 2. **Silent Error Handling in GeneratorController**

**Location:** `GeneratorController.swift:81-87`

**Problem:**
```swift
} catch let error as LanguageModelSession.GenerationError {
    print(error.localizedDescription)  // ❌ Only prints to console
} catch let error as LanguageModelSession.ToolCallError {
    print(error.tool)  // ❌ Lost error
} catch {
    print(error.localizedDescription)  // ❌ User never sees error
}
```

**Fix:**
```swift
@MainActor
extension GeneratorSessionModel {
    var errorMessage: String?
}

// In controller:
} catch let error as LanguageModelSession.GenerationError {
    model.errorMessage = formatError(error)
} catch {
    model.errorMessage = error.localizedDescription
}

// UI can now show:
if let error = controller.model.errorMessage {
    Text(error).foregroundStyle(.red)
}
```

#### 3. **Missing Cancellation Support**

**Problem:**
```swift
@MainActor func request(message: String) {
    Task {  // ❌ No way to cancel
        for try await partialResponse in stream { ... }
    }
}
```

**Fix:**
```swift
@MainActor
final class AdventureSessionModel {
    private(set) var currentTask: Task<Void, Never>?

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
}

@MainActor func request(message: String) {
    model.cancel()  // Cancel previous request

    model.currentTask = Task {
        do {
            for try await partialResponse in stream {
                try Task.checkCancellation()
                self.model.adventureChat = partialResponse.content
            }
        } catch is CancellationError {
            // Clean cancellation
        } catch { ... }
    }
}
```

---

### ⚠️ Design Issues

#### 4. **PartiallyGenerated Type Not Fully Utilized**

**Observation:**
```swift
// In GeneratorController:
var extracted: BlockGenModel.PartiallyGenerated?

// But in AdventureSessionModel:
var extracted: [BlockEntryGenModel.PartiallyGenerated] = []
```

**Issue:** Inconsistent use of `PartiallyGenerated` vs fully-formed types.

**`PartiallyGenerated` Benefits:**
- Real-time streaming updates for nested structures
- Progressive disclosure (show partial results while generating)

**Recommendation:**
```swift
// Consistent pattern:
@MainActor
final class AdventureSessionModel {
    var partialCampaign: CampaignGenModel.PartiallyGenerated?
    var finalCampaign: CampaignGenModel?

    func finalize() throws {
        guard let partial = partialCampaign else { return }
        finalCampaign = try CampaignGenModel(partial.rawContent)
    }
}
```

#### 5. **Session Management Confusion**

**Problem:**
```swift
@MainActor
final class GeneratorSessionModel {
    var session = LanguageModelSession()  // Generic session

    func set(session: LanguageModelSession) {
        self.session = session
    }
}
```

**Issues:**
- Single session used for multiple purposes (character, adventure, extraction)
- Changing instructions mid-session loses context
- No clear session lifecycle

**Better Design:**
```swift
@MainActor
final class GeneratorSessionCoordinator {
    private(set) var characterSession: LanguageModelSession?
    private(set) var adventureSession: LanguageModelSession?
    private(set) var extractorSession: LanguageModelSession?

    func setupCharacterSession() {
        characterSession = LanguageModelSession {
            "You are an assistant for creating RPG characters."
        }
        characterSession?.prewarm()
    }

    func setupAdventureSession() {
        adventureSession = LanguageModelSession {
            "You are an assistant for creating RPG adventures."
        }
        adventureSession?.prewarm()
    }

    // Clear separation of concerns
}
```

#### 6. **Missing Token/Cost Awareness**

**Observation:** No tracking of:
- Token usage per session
- Rate limit proximity
- Context window utilization

**Recommendation:**
```swift
@MainActor
final class TokenTracker {
    private(set) var estimatedTokensUsed: Int = 0
    private(set) var requestCount: Int = 0

    func trackRequest(_ prompt: String, response: String) {
        // Rough estimation: ~4 chars per token
        let tokens = (prompt.count + response.count) / 4
        estimatedTokensUsed += tokens
        requestCount += 1
    }

    var isNearRateLimit: Bool {
        requestCount > 80  // Heuristic - actual limits unknown
    }
}
```

---

### 🔧 Minor Issues

#### 7. **Inconsistent Error Clearing**

**AdventureGeneratorController:**
```swift
var responseErrorContent: String = ""
```
Never cleared on success.

**Fix:**
```swift
// On successful response:
model.responseErrorContent = ""
```

#### 8. **Unused Reference Code**

**GeneratorController.swift:40-46:**
```swift
// Commented-out reference example
// let reference: CharacterGenModel = CharacterGenModel(...)
```

**Action:** Either remove or document as "Example for testing"

#### 9. **Typo in Instructions**

**AdventureGeneratorController.swift:36:**
```swift
"Keep your answer pricse except..."  // ❌ "pricse"
```

**Should be:** "precise"

#### 10. **Markdown Cleaning Too Aggressive**

**FoundationManager.swift:37-44:**
```swift
func minimizeMarkDown(_ content: String) -> String {
    let tags = ["#", "##", "###", "####", "---"]
    content.replacingOccurrences(of: tag, with: "")
}
```

**Issue:** Removes ALL occurrences of `#`, including in normal text.

**Fix:**
```swift
func minimizeMarkDown(_ content: String) -> String {
    var lines = content.components(separatedBy: .newlines)
    lines = lines.map { line in
        // Only remove if at start of line
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        while trimmed.hasPrefix("#") {
            trimmed.removeFirst()
        }
        if trimmed.hasPrefix("---") {
            return ""
        }
        return trimmed.trimmingCharacters(in: .whitespaces)
    }
    return lines.joined(separator: "\n")
}
```

---

## Performance Considerations

### 1. **Prewarming Strategy**

**Current:**
```swift
session.prewarm()  // Called after session creation
```

**Optimization:**
```swift
// Prewarm all sessions on app launch (background thread)
Task(priority: .utility) {
    await characterController.generate()
    await adventureController.generate()
    await extractorController.generateExtractor(from: model)
}
```

### 2. **Streaming vs Batch**

**Current:** All requests use streaming.

**When to Use Batch:**
- Small, quick generations (e.g., single name)
- Background processing where UI updates aren't needed

```swift
// For single-response needs:
let response = try await session.respond(to: prompt)
// vs streaming:
for try await partial in session.streamResponse(to: prompt) { ... }
```

### 3. **Context Window Management**

**Risk:** Long sessions may exceed context window.

**Solution:**
```swift
@MainActor
final class SessionManager {
    private var turnCount = 0

    func shouldResetSession() -> Bool {
        turnCount > 10  // Heuristic
    }

    func trackTurn() {
        turnCount += 1
        if shouldResetSession() {
            // Summarize and create new session
        }
    }
}
```

---

## Testing Recommendations

### Unit Tests

```swift
@Test func testCharacterGeneration() async throws {
    let controller = GeneratorController()
    await controller.generate()

    let message = "Create a dwarf fighter named Thorin"
    try await controller.request(message: message)

    #expect(controller.model.characterChat != nil)
    #expect(controller.model.characterChat?.contains("Thorin") == true)
}

@Test func testAvailabilityCheck() {
    let manager = FoundationManager()
    let isAvailable = manager.checkIsAvailable()

    if !isAvailable {
        #expect(manager.notAvailableReason != "")
    }
}
```

### Integration Tests

```swift
@Test func testAdventureExtraction() async throws {
    let controller = GeneratorController()
    controller.generateExtractor(from: mockModel)

    let dungeonText = """
    1. GUARDROOM Two drunken brigands snore heavily.
    2. EMPTY ROOM There is an apple on the floor.
    """

    try await controller.requestExtraction(message: dungeonText)

    let extracted = try #require(controller.model.extracted)
    #expect(extracted.entries.count == 2)
}
```

### UI Tests

```swift
@Test func testLanguageSupportUI() {
    let view = CheckLanguageSupport()
        .environment(FoundationManager())
        .environment(\.locale, Locale(identifier: "de"))

    // Verify language support indicator shows
}
```

---

## Privacy & Security Considerations

### 1. **On-Device Processing**

**Good:** FoundationModels runs entirely on-device (with Apple Silicon Neural Engine).

**Implications:**
- No data sent to cloud
- Works offline (after model download)
- Respects user privacy

### 2. **Guardrails**

**Observed:**
```swift
case .guardrailViolation(let context):
    model.responseErrorContent = "Guardrail Violation: ..."
```

**What it means:**
- Apple Intelligence has built-in content filtering
- May reject violent/adult content depending on system settings
- RPG content (fantasy violence, alcohol mentions) *could* trigger guardrails

**Mitigation:**
- Clear system instructions emphasizing fictional context
- Catch guardrail errors and suggest rephrasing

### 3. **User Data**

**Current:** No apparent logging/telemetry of user prompts.

**Recommendation:** Add opt-in analytics:
```swift
struct GeneratorAnalytics {
    func trackGeneration(type: GenerationType, success: Bool) {
        // Privacy-preserving metrics only (no content)
    }
}
```

---

## Future Enhancements

### 1. **Multi-Turn Adventures with Memory**

**Concept:** Maintain context across sessions using custom memory:

```swift
struct AdventureMemory: Codable {
    var previousScenarios: [String]
    var establishedCharacters: [String]
    var worldRules: [String]
}

func createPromptWithMemory(message: String, memory: AdventureMemory) -> Prompt {
    Prompt {
        """
        Previous scenarios: \(memory.previousScenarios.joined(separator: ", "))
        Established characters: \(memory.establishedCharacters.joined(separator: ", "))

        User request: \(message)
        """
    }
}
```

### 2. **Hybrid Generation**

**Idea:** Combine multiple models for different tasks:

```swift
let summarizer = SystemLanguageModel(useCase: .summarization)
let contentTagger = SystemLanguageModel(useCase: .contentTagging)
let defaultModel = SystemLanguageModel.default

// Step 1: Generate with default
let adventure = try await defaultSession.respond(to: prompt, generating: AdventureGenModel.self)

// Step 2: Summarize with specialized model
let summarySession = LanguageModelSession(model: summarizer)
let summary = try await summarySession.respond(to: Prompt { adventure.description })

// Step 3: Tag with content tagger
let tagSession = LanguageModelSession(model: contentTagger)
let tags = try await tagSession.respond(to: Prompt { adventure.description })
```

### 3. **Batch Export**

**Use Case:** Generate entire campaign at once:

```swift
@MainActor func generateCampaign(theme: String) async throws -> CampaignGenModel {
    let prompt = Prompt {
        """
        Create a complete 5-adventure campaign with theme: \(theme)
        Each adventure should have 5 scenarios.
        Each scenario should have 10 detailed entries.
        """
    }

    let stream = session.streamResponse(to: prompt, generating: CampaignGenModel.self)

    var latestCampaign: CampaignGenModel.PartiallyGenerated?
    for try await partial in stream {
        latestCampaign = partial.content
        // Update progress UI
    }

    guard let final = latestCampaign else {
        throw GenerationError.noContent
    }
    return try CampaignGenModel(final.rawContent)
}
```

### 4. **Image Generation Integration**

**Future:** When Apple adds image generation to FoundationModels:

```swift
@Generable
struct VisualCharacterGenModel {
    var character: CharacterGenModel
    @Guide(description: "Physical description for image generation")
    var visualDescription: String
}

// Generate image from description
let imageModel = SystemImageModel.default
let image = try await imageModel.generate(prompt: character.visualDescription)
```

### 5. **Voice Input/Output**

**Concept:** Integrate with Speech framework:

```swift
import Speech

class VoiceAdventureController {
    func generateFromVoice() async throws {
        let recognizer = SFSpeechRecognizer()!
        let request = SFSpeechAudioBufferRecognitionRequest()

        let result = try await recognizer.recognitionTask(with: request).result
        let transcript = result.bestTranscription.formattedString

        try await adventureController.request(message: transcript)
    }
}
```

---

## Recommendations Summary

### Immediate (P0)
1. ✅ Remove unstructured `Task` wrappers - make `request()` methods `async throws`
2. ✅ Add proper error propagation to UI
3. ✅ Implement cancellation support
4. ✅ Fix typo in instructions ("pricse" → "precise")

### Short-Term (P1)
5. ✅ Add separate sessions per generation type
6. ✅ Implement token usage tracking
7. ✅ Clear error messages on successful requests
8. ✅ Improve markdown cleaning logic
9. ✅ Add unit tests for controllers

### Medium-Term (P2)
10. ✅ Add session memory/context management
11. ✅ Implement progress indicators for long generations
12. ✅ Add user-facing error recovery suggestions
13. ✅ Optimize prewarming strategy

### Long-Term (P3)
14. ✅ Explore multi-model hybrid generation
15. ✅ Add voice input/output
16. ✅ Prepare for image generation integration
17. ✅ Build comprehensive test suite

---

## Conclusion

The GeneratorRPG module demonstrates **strong foundation model integration** with Apple's FoundationModels framework. The use of `@Generable` for structured generation is particularly well-executed, providing type-safe AI outputs for complex nested data.

**Strengths:**
- Proper availability checking
- Streaming for responsive UI
- Type-safe structured generation
- Comprehensive error handling (in AdventureGeneratorController)
- Good separation of concerns (BasicAI vs Controllers vs Models)

**Key Improvements Needed:**
- Structured concurrency (remove unstructured Tasks)
- Cancellation support
- Consistent error handling across all controllers
- Session lifecycle management

**Overall Assessment:** 7/10 - Solid implementation with room for concurrency and error handling improvements. The structured generation capabilities are well-designed and the code is ready for production with the recommended P0 fixes.
