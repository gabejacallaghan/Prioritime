# Time Tracker

A small iOS app (iOS 16+) for logging how much time you spend on things — class, homework, paid work, social time, prayer, and so on — and seeing week-by-week and month-by-month where that time actually went.

## Features

- **Log (home screen):** choose an activity, set the time on Timer-style wheels (hours plus 5-minute steps), pick the date, add an optional note, and tap **Log**. Today's entries appear underneath. Tap one to edit it, or long-press it to delete it.
- **Stats:** switch between Week and Month and step back through earlier periods.
  - A horizontal bar chart ranks activities from most to least time.
  - A stacked day-by-day chart shows how the time was spread across the period.
  - Short, factual insights cover: the most and least time, the change from the previous period (compared at the same point while a period is still in progress), the biggest increase and decrease, the busiest day and daily average, the most consistent activity, and any activities with nothing logged.
- **Check-in:** a once-a-day "How was your day?" with a 1–5 rating, optional feeling tags (happy, tired, lonely, … plus your own) and an optional written note. Settings let you pick the reminder time and turn the tags and note on or off. If the reminder time has passed and you haven't checked in, a prompt appears on the Log screen. Check-ins show up in Stats as a mood chart, common tags, and extra insights.
- **Insights (Stats → Insights):** sends a summary of your time log and check-ins to Claude and shows the patterns it finds. It's prompted to show sample sizes, avoid treating correlation as cause, and include uncomfortable findings. See *AI Insights and privacy* below.
- **Activities:** add, rename, recolor, change the icon, reorder or delete activities.
- **History:** reached from the clock icon on the Log screen. Lists every entry grouped by day; swipe to delete, tap to edit.

## AI Insights and privacy

The Insights button calls the Anthropic API directly from the phone, so you supply your own API key (console.anthropic.com). The key is stored in the iOS Keychain and only sent to `api.anthropic.com`. Nothing is sent until you tap *Analyze*; the sheet shows exactly what will be sent (totals, per-day time, mood and tags). Written notes are excluded unless you switch them on. The request uses `claude-opus-5-5` with the server-side fallback option enabled.

A key stored in an app is fine for personal use but is not suitable for a public App Store release. For that, route requests through your own backend that holds the key.

Everything else is stored on the device as JSON (`Documents/timetracker.json`). There's no account, and the only network access is the optional AI Insights request above.

## Building

Requirements: Xcode 14 or later. The target is iOS 16.0. The app uses SwiftUI, Swift Charts and UIKit's `UIPickerView` (for the wheels), with no third-party dependencies.

1. Open `TimeTracker.xcodeproj`.
2. Select the **TimeTracker** target → *Signing & Capabilities* → choose your Team. Change the bundle identifier if needed.
3. Pick a simulator or your iPhone and press **Run**.

## Code layout

| File | Purpose |
| --- | --- |
| `TimeTrackerApp.swift` | App entry point and tab bar |
| `Models.swift` | `Activity`, `TimeEntry`, color/icon palette, duration formatting, week/month periods |
| `DataStore.swift` | Observable store with JSON persistence |
| `DurationWheelPicker.swift` | Hours/minutes wheel picker with fixed unit labels |
| `LogView.swift` | Home/entry screen and shared row components |
| `StatsView.swift` | Charts and the summary for the selected week or month |
| `InsightsEngine.swift` | Generates the trend insights |
| `ActivitiesView.swift` | Activity list and editor |
| `HistoryView.swift` | All entries and the entry editor |
| `CheckIn.swift` | Check-in models, mood tags, and mood insights |
| `CheckInViews.swift` | Check-in tab, editor, settings, Log prompt, mood chart card |
| `NotificationManager.swift` | Daily reminder scheduling and notification tap handling |
| `AIInsights.swift` | Keychain helper, payload builder, Anthropic API client |
| `AIInsightsView.swift` | The Insights sheet |
