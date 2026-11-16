// @copyright André Trettin

import CoreRPG
import SwiftUI
import WidgetKit

private struct ContentWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ContentWidgetSnapshot

    // Shared by the small and medium views. See CODE_AUDIT_26 §9.56.
    var moduleTitle: LocalizedStringKey {
        snapshot.module == .value ? "Characters" : "Adventures"
    }

    var moduleIcon: String {
        snapshot.module == .value ? "person.crop.circle" : "book.closed"
    }

    var countLabel: LocalizedStringKey {
        snapshot.module == .value ? "characters" : "adventures"
    }
}

private struct ContentWidgetProvider: TimelineProvider {
    let module: NetworkModules

    func placeholder(in context: Context) -> ContentWidgetEntry {
        ContentWidgetEntry(date: .now, snapshot: previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (ContentWidgetEntry) -> Void) {
        completion(ContentWidgetEntry(
            date: .now,
            snapshot: context.isPreview ? previewSnapshot : ContentWidgetSnapshot.load(for: module)
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContentWidgetEntry>) -> Void) {
        let entry = ContentWidgetEntry(
            date: .now,
            snapshot: ContentWidgetSnapshot.load(for: module)
        )
        completion(Timeline(entries: [entry], policy: .never))
    }

    private var previewSnapshot: ContentWidgetSnapshot {
        ContentWidgetSnapshot(
            module: module,
            totalCount: 3,
            items: [
                ContentWidgetItem(id: UUID(), name: "The Wanderer"),
                ContentWidgetItem(id: UUID(), name: "Moonlit Keep"),
                ContentWidgetItem(id: UUID(), name: "Hidden Passage")
            ]
        )
    }
}

private struct ContentWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: ContentWidgetEntry

    var body: some View {
        Group {
            if family == .systemSmall {
                ContentWidgetSmallContentView(entry: entry)
            } else {
                ContentWidgetMediumContentView(entry: entry)
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(smallDestination)
    }

    private var smallDestination: URL? {
        guard family == .systemSmall else { return nil }
        if let first = entry.snapshot.items.first {
            return entry.snapshot.itemURL(for: first)
        }
        return entry.snapshot.rootURL
    }
}

private struct ContentWidgetSmallContentView: View {
    let entry: ContentWidgetEntry

    var body: some View {
        VStack(alignment: .leading) {
            Image(systemName: entry.moduleIcon)
                .font(.title)
                .foregroundStyle(.tint)
                .widgetAccentable()
                .accessibilityHidden(true)
            Spacer()
            Text(entry.moduleTitle)
                .font(.headline)
            Text(entry.snapshot.totalCount, format: .number)
                .font(.title)
                .bold()
            Text(entry.countLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The names are the point of the widget, so they are shown on the Home Screen. Where the system
/// redacts private content (a locked device in StandBy, for one) `privacySensitive()` hides them
/// and the count stays. See CODE_AUDIT_26 §6.17.
private struct ContentWidgetMediumContentView: View {
    let entry: ContentWidgetEntry

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Label(entry.moduleTitle, systemImage: entry.moduleIcon)
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .widgetAccentable()
                Spacer()
                Text(entry.snapshot.totalCount, format: .number)
                    .bold()
                    // The number stays the value; the label alone replaced it. See CODE_AUDIT_26 §8.4.
                    .accessibilityLabel(Text(entry.countLabel))
                    .accessibilityValue(Text(entry.snapshot.totalCount, format: .number))
            }
            Divider()
            if entry.snapshot.items.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text("No Items", bundle: .main)
                    } icon: {
                        Image(systemName: entry.moduleIcon)
                    }
                } description: {
                    Text("Create one in MasterRPG.", bundle: .main)
                }
            } else {
                ForEach(entry.snapshot.items.prefix(3)) { item in
                    if let destination = entry.snapshot.itemURL(for: item) {
                        Link(destination: destination) {
                            HStack {
                                Text(verbatim: item.name)
                                    .lineLimit(1)
                                    .privacySensitive()
                                Spacer()
                                Image(systemName: "chevron.forward")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: item.name))
                    }
                }
            }
        }
    }
}

struct CharacterContentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: ContentWidgetKind.characters,
            provider: ContentWidgetProvider(module: .value)
        ) { entry in
            ContentWidgetView(entry: entry)
        }
        .configurationDisplayName("Characters")
        .description("See your characters and open them in MasterRPG.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct AdventureContentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: ContentWidgetKind.adventures,
            provider: ContentWidgetProvider(module: .adventure)
        ) { entry in
            ContentWidgetView(entry: entry)
        }
        .configurationDisplayName("Adventures")
        .description("See your adventures and open them in MasterRPG.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview("Characters", as: .systemSmall) {
    CharacterContentWidget()
} timeline: {
    ContentWidgetEntry(
        date: .now,
        snapshot: ContentWidgetSnapshot(
            module: .value,
            totalCount: 3,
            items: [ContentWidgetItem(id: UUID(), name: "The Wanderer")]
        )
    )
}

#Preview("Adventures", as: .systemMedium) {
    AdventureContentWidget()
} timeline: {
    ContentWidgetEntry(
        date: .now,
        snapshot: ContentWidgetSnapshot(
            module: .adventure,
            totalCount: 2,
            items: [
                ContentWidgetItem(id: UUID(), name: "Moonlit Keep"),
                ContentWidgetItem(id: UUID(), name: "Hidden Passage")
            ]
        )
    )
}
