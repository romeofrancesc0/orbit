import AppKit
import SwiftUI

/// `Orbit --demo`: la notch con dati inventati, per gli screenshot e per provare
/// un layout senza mostrare i propri progetti. Non legge né scrive nulla di reale.
@MainActor
enum DemoData {
    static let notes = "Review the hotfix round\nCall the accountant"

    static var sessions: [AgentSession] {
        let now = Date()
        func session(
            _ id: String, provider: String = "Claude Code", accent: String = "#D97757",
            title: String, project: String, branch: String? = "main", status: SessionStatus,
            activity: String?, ago: TimeInterval, tokens: Int?, host: String? = "Desktop"
        ) -> AgentSession {
            AgentSession(
                id: "demo:\(id)",
                providerID: provider.lowercased().replacingOccurrences(of: " ", with: "-"),
                providerName: provider,
                accentHex: accent,
                title: title,
                project: project,
                path: "/tmp/\(project)",
                branch: branch,
                model: "claude-opus",
                status: status,
                activity: activity,
                host: host,
                startedAt: now.addingTimeInterval(-ago - 1800),
                updatedAt: now.addingTimeInterval(-ago),
                tokensUsed: tokens,
                tokenLimit: tokens == nil ? nil : 200_000,
                nativeID: id
            )
        }
        return [
            session("a", title: "Update the authentication flow", project: "atlas-api", branch: "feat/auth", status: .blocked, activity: "Bash · rm -rf build/", ago: 12, tokens: 88_000),
            session("b", title: "New pricing page", project: "website", status: .attention, activity: "The page is done, should I check mobile too?", ago: 95, tokens: 142_000, host: "Terminale"),
            session("c", title: "Database migration", project: "harbor", branch: "db/v2", status: .working, activity: "Edit · schema.prisma", ago: 3, tokens: 61_000),
            session("d", provider: "Codex", accent: "#10A37F", title: "Checkout integration tests", project: "shop-core", status: .working, activity: "pnpm test --filter checkout", ago: 8, tokens: 37_000, host: "Codex"),
            session("g", title: "Release notes draft", project: "docs-site", branch: "main", status: .done, activity: "Done: the draft is in docs/releases.md", ago: 240, tokens: 47_000, host: "Desktop"),
            session("e", title: "Parser refactor", project: "compiler", branch: "refactor/parser", status: .idle, activity: nil, ago: 900, tokens: 120_000, host: "VS Code"),
            session("f", title: "Notes indexing", project: "notes-ai", status: .ended, activity: nil, ago: 7200, tokens: 54_000, host: nil)
        ]
    }

    static func seed(_ services: AppServices) {
        services.media.seedForPreview(
            NowPlaying(
                title: "Nocturne in F minor",
                artist: "Orbit Ensemble",
                album: "Midnight",
                duration: 248,
                elapsed: 71,
                rate: 1,
                timestamp: Date(),
                isPlaying: true,
                bundleID: "com.apple.Music",
                parentBundleID: nil,
                appName: "Music",
                artworkID: "demo",
                shuffle: 1,
                repeatMode: 1
            ),
            artwork: artwork
        )

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }
        let soon = Date().addingTimeInterval(1500)
        services.calendar.seedForPreview(
            events: [
                CalendarEventItem(id: "1", title: "Team standup", start: soon, end: soon.addingTimeInterval(900), isAllDay: false, colorHex: "#5AC8FA", calendarName: "Work", meetingURL: URL(string: "https://meet.google.com/demo")),
                CalendarEventItem(id: "2", title: "Design review", start: soon.addingTimeInterval(5400), end: soon.addingTimeInterval(9000), isAllDay: false, colorHex: "#FF8A5C", calendarName: "Work"),
                CalendarEventItem(id: "3", title: "Gym", start: at(19), end: at(20, 30), isAllDay: false, colorHex: "#4ADE80", calendarName: "Personal")
            ],
            reminders: [
                ReminderItem(id: "r1", title: "Send the invoice", due: nil, colorHex: "#FFC145")
            ]
        )

        services.battery.seedForPreview(BatteryState(hasBattery: true, level: 0.82, isCharging: false, isPluggedIn: false, minutesRemaining: 388))
        services.system.seedForPreview(SystemSnapshot(
            cpu: 0.34,
            memory: 0.62,
            memoryUsedGB: 14.8,
            memoryTotalGB: 24,
            disk: 0.47,
            diskFreeGB: 512,
            networkDownPerSecond: 1_240_000,
            networkUpPerSecond: 86_000,
            cpuHistory: (0..<30).map { 0.28 + 0.2 * abs(sin(Double($0) / 3.1)) }
        ))
        services.shelf.seedForPreview([
            ShelfItem(kind: .link, name: "developer.apple.com", value: "https://developer.apple.com"),
            ShelfItem(kind: .text, name: "Draft reply to the client", value: "Draft reply to the client")
        ])
        services.clipboard.seedForPreview([
            ClipboardEntry(content: .text("git rebase -i HEAD~3"), sourceApp: "Terminal", copiedAt: Date()),
            ClipboardEntry(content: .text("https://github.com/"), sourceApp: "Safari", copiedAt: Date()),
            ClipboardEntry(content: .text("See you at 3 for the review"), sourceApp: "Messages", copiedAt: Date())
        ])
    }

    /// Una copertina inventata: una luna su un cielo al tramonto.
    private static var artwork: NSImage {
        let size = NSSize(width: 500, height: 500)
        return NSImage(size: size, flipped: false) { rect in
            let sky = NSGradient(colors: [
                NSColor(calibratedRed: 0.10, green: 0.07, blue: 0.27, alpha: 1),
                NSColor(calibratedRed: 0.55, green: 0.16, blue: 0.47, alpha: 1),
                NSColor(calibratedRed: 0.98, green: 0.52, blue: 0.32, alpha: 1)
            ])
            sky?.draw(in: rect, angle: -90)
            let moon = NSBezierPath(ovalIn: NSRect(x: 150, y: 190, width: 200, height: 200))
            NSColor(calibratedRed: 1, green: 0.93, blue: 0.78, alpha: 1).setFill()
            moon.fill()
            let shade = NSBezierPath(ovalIn: NSRect(x: 196, y: 214, width: 190, height: 190))
            NSColor(calibratedRed: 0.33, green: 0.12, blue: 0.40, alpha: 1).setFill()
            shade.fill()
            return true
        }
    }
}
