import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.load())
        // Doar o sugestie pentru sistem — cadența reală de refresh a widget-urilor nu e
        // garantată/controlabilă exact (comparabil cu constrângerile de fundal de pe Android).
        // Aplicația principală oricum cere un refresh explicit (reloadTimelines) de fiecare
        // dată când datele se schimbă, deci timpul ăsta e doar un fallback.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct FriendCampWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Provider.Entry

    var body: some View {
        if let snapshot = entry.snapshot {
            content(for: snapshot)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "tent.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Deschide FriendCamp")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func content(for snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.green)
                Text("\(snapshot.onlineCount)/\(snapshot.totalCount) online")
                    .font(.headline)
            }
            if let lastActivityDate = snapshot.lastActivityDate {
                Text("Ultima activitate \(lastActivityDate, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if family == .systemMedium, let title = snapshot.latestPostTitle {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Label("Ultima postare", systemImage: "doc.text.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text(title)
                        .font(.subheadline.bold())
                        .lineLimit(2)
                    if let author = snapshot.latestPostAuthor {
                        Text("de \(author)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct FriendCampWidget: Widget {
    let kind: String = "FriendCampWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            FriendCampWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("FriendCamp")
        .description("Statistici rapide despre grupul tău de camping.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    FriendCampWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: WidgetSnapshot(
        onlineCount: 3, totalCount: 5, lastActivityDate: Date(),
        latestPostTitle: "Drumeție la cascadă", latestPostAuthor: "Ana",
        latestPostDate: Date(), generatedAt: Date()
    ))
}
