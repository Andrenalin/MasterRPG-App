# PDF Content Extraction with Foundation Models

## Overview

The PDF Content Extraction feature uses Apple's Foundation Models (on-device AI) to automatically extract structured metadata from RPG PDF documents, including rulebooks, adventures, campaigns, and supplements.

## Architecture

### GeneratorRPG Module (Core AI Implementation)

Located in `Modules/GeneratorRPG/FoundationLabCore/`:

- **Models/** - `PdfExtractedContent.swift`
  - `@Generable` structures for extracted content
  - Type-safe structured output from Foundation Models

- **Providers/** - Implementation files
  - `PdfContentExtracting.swift` - Protocol definition
  - `FoundationModelsPdfContentExtractor.swift` - Main extraction logic

- **Capabilities/** - Use cases
  - `ExtractPdfContentUseCase.swift` - Clean API for extraction

### PdfRPG Module (Integration)

Located in `Modules/PdfRPG/`:

- **Controller/** - `PdfContentExtractorController.swift`
  - Observable controller for SwiftUI integration
  - Progress tracking and error handling

- **Model/** - `PdfModel+ContentExtraction.swift`
  - Extensions to apply extracted content to PdfModel

- **Pdf/** - View components
  - `PdfContentExtractionView.swift` - Reusable extraction UI
  - `PdfImportWithExtractionView.swift` - Complete import workflow

## Features

### ✅ Automatic Extraction

- **Title** - Document name
- **Summary** - 2-3 sentence overview
- **Tags** - 3-8 relevant keywords (genre, setting, system, theme)
- **Sections** - Major chapters/sections with summaries
- **Document Type** - Classification (rulebook, adventure, supplement, etc.)

### ✅ Streaming Support

Progressive UI updates as content is generated:
1. Title appears first (~0.3s)
2. Summary generates (~1s)
3. Tags populate (~1.5s)
4. Sections stream in (~2-3s)

### ✅ Smart Error Handling

- Availability checks (Apple Intelligence required)
- Context overflow handling (automatic truncation to 10,000 chars)
- Guardrail violation detection
- Clear user-facing error messages

### ✅ Privacy First

- 100% on-device processing
- No data sent to external servers
- Works offline
- Respects user privacy settings

## Usage

### Basic Extraction

```swift
import GeneratorRPG
import PDFKit

let extractor = FoundationModelsPdfContentExtractor()

// Simple extraction
let content = try await extractor.extract(from: pdfDocument)

print(content.title)
print(content.summary)
print(content.tags)
```

### Extraction with Progress

```swift
let content = try await extractor.extractWithProgress(from: pdfDocument) { partial in
    // Update UI as content streams in
    if let title = partial.title {
        titleLabel.text = title
    }
    if let tags = partial.tags {
        updateTagsUI(tags)
    }
}
```

### Using the Controller (Recommended for SwiftUI)

```swift
import SwiftUI
import GeneratorRPG

struct MyPdfView: View {
    @State private var controller = PdfContentExtractorController()
    let pdfDocument: PDFDocument

    var body: some View {
        VStack {
            if controller.isExtracting {
                ProgressView("Analyzing PDF...")
            } else {
                Button("Extract Content") {
                    Task {
                        if let content = await controller.extractWithProgress(from: pdfDocument) {
                            // Use extracted content
                            print(content.title)
                        }
                    }
                }
            }

            if let error = controller.lastError {
                Text(error).foregroundStyle(.red)
            }
        }
    }
}
```

### Complete Import Workflow

```swift
// Use the pre-built import view
PdfImportWithExtractionView(
    pdfDocument: pdfDocument,
    fileUrl: fileUrl
) { pdfModel in
    // Save the created model
    savePdfModel(pdfModel)
}
```

### Applying to Existing Models

```swift
// Apply extracted content to existing PdfModel
let content = try await extractor.extract(from: pdfDocument)

pdfModel.applyExtractedContent(content, updateExisting: false)

// Or create new model from content
let newModel = PdfModel.from(
    extractedContent: content,
    fileUrl: fileUrl
)
```

## Use Case Patterns

### Pattern 1: PDF Import with AI

```swift
// User imports a PDF file
let pdfUrl = selectedFileUrl
let pdfDocument = PDFDocument(url: pdfUrl)!

// Extract content automatically
let useCase = ExtractPdfContentUseCase()
let content = try await useCase.execute(pdfDocument: pdfDocument)

// Create model with extracted data
let model = PdfModel.from(extractedContent: content, fileUrl: fileUrl)

// Save to Core Data
saveToPersistentStore(model)
```

### Pattern 2: Enhance Existing PDFs

```swift
// User has PDFs with minimal metadata
for pdfModel in incompletePdfs {
    guard let url = pdfModel.fileUrl?.url,
          let pdfDocument = PDFDocument(url: url) else { continue }

    let useCase = ExtractPdfContentUseCase()
    let content = try await useCase.execute(pdfDocument: pdfDocument)

    // Only update empty fields
    pdfModel.applyExtractedContent(content, updateExisting: true)
}
```

### Pattern 3: Smart Search/Categorization

```swift
// Extract content for better search
let content = try await extractor.extract(from: pdfDocument)

// Use tags for smart categorization
let isRulebook = content.documentType == .rulebook
let isDnD = content.tags.contains { $0.localizedCaseInsensitiveContains("D&D") }

// Auto-file in correct category
if isRulebook && isDnD {
    pdfModel.category = .rules
    pdfModel.tags.append("D&D 5e")
}
```

## Configuration

### Custom Instructions

```swift
let customExtractor = FoundationModelsPdfContentExtractor(
    maxPages: 20, // Process more pages
    maxCharacters: 12000, // Allow more content
    instructions: """
    Focus on extracting game mechanics and rules references.
    Prioritize spell lists, equipment tables, and stat blocks.
    """
)
```

### Page Limits

| Page Limit | Chars | Tokens (approx) | Use Case |
|------------|-------|-----------------|----------|
| 10 pages | 6,000 | ~2,000 | Quick previews |
| 15 pages (default) | 9,000 | ~3,000 | Balanced extraction |
| 20 pages | 12,000 | ~4,000 | Comprehensive analysis |

⚠️ **Stay under 4096 token limit** (input + output combined)

## Error Handling

### Required Error Handling

```swift
do {
    let content = try await extractor.extract(from: pdfDocument)
} catch PdfExtractionError.emptyDocument {
    showAlert("PDF contains no readable text")
} catch PdfExtractionError.modelUnavailable {
    showAlert("Apple Intelligence not available on this device")
} catch PdfExtractionError.contentTooLarge {
    // Automatic truncation occurred, content is still usable
    logWarning("PDF was truncated to fit context window")
} catch {
    showAlert("Extraction failed: \(error.localizedDescription)")
}
```

### Availability Check

```swift
// Always check before showing extraction UI
let controller = PdfContentExtractorController()
controller.checkModelAvailability()

if !controller.isModelAvailable {
    // Hide extraction features
    // Show manual entry UI instead
}
```

## Performance

### Typical Extraction Times

- **Small PDF** (1-5 pages): 1-2 seconds
- **Medium PDF** (6-15 pages): 2-4 seconds
- **Large PDF** (16-20 pages): 3-5 seconds

### Optimization Tips

1. **Prewarm sessions** - Sessions are prewarmed automatically
2. **Limit pages** - Default 15 pages balances quality and speed
3. **Use streaming** - Shows progress, improves perceived performance
4. **Cache results** - Store extracted content, don't re-extract

## Testing

### Unit Tests

```swift
@Test("Extract content from sample PDF")
func testPdfExtraction() async throws {
    let pdfUrl = Bundle.module.url(forResource: "sample", withExtension: "pdf")!
    let pdfDocument = PDFDocument(url: pdfUrl)!

    let extractor = FoundationModelsPdfContentExtractor()
    let content = try await extractor.extract(from: pdfDocument)

    #expect(content.title.isEmpty == false)
    #expect(content.tags.count >= 3)
    #expect(content.documentType != .other)
}
```

### Preview Testing

```swift
#Preview("Extraction Flow") {
    if let url = Bundle.main.url(forResource: "test", withExtension: "pdf"),
       let doc = PDFDocument(url: url) {
        PdfImportWithExtractionView(pdfDocument: doc, fileUrl: nil) { _ in }
    }
}
```

## Best Practices

### ✅ DO

- Check `isModelAvailable` before showing extraction UI
- Use streaming for better UX
- Handle all error cases gracefully
- Provide manual entry fallback
- Cache extracted content
- Show progress during extraction

### ❌ DON'T

- Don't assume Apple Intelligence is available
- Don't block UI thread (use `async`/`await`)
- Don't extract same PDF multiple times
- Don't exceed 4096 token limit
- Don't use for world knowledge queries
- Don't send user PDFs to external servers

## Troubleshooting

### "Model Unavailable"

**Cause**: Apple Intelligence not available on device
**Solution**: Check device compatibility, region, and user opt-in

### "Content Too Large"

**Cause**: PDF exceeds token limit
**Solution**: Reduce `maxPages` or `maxCharacters`, or extract sections separately

### "Text Extraction Failed"

**Cause**: PDF is image-based or encrypted
**Solution**: Show manual entry form, or use OCR preprocessing

### Slow Performance

**Cause**: Large PDF or cold start
**Solution**: Prewarm sessions, reduce page count, show streaming progress

## Requirements

- iOS 26+ / macOS 26+ / visionOS 26+
- Apple Intelligence enabled
- On-device Foundation Models available

## References

- [Foundation Models Documentation](https://developer.apple.com/documentation/foundationmodels)
- [WWDC Sessions](https://developer.apple.com/videos/wwdc2025)
- `axiom-foundation-models` skill in Claude Code

---

**Created**: 2026-03-26
**Last Updated**: 2026-03-26
**Version**: 1.0.0
