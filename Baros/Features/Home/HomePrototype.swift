// PROTOTYPE — throwaway. Three Home redesign variants plus the current Home, switchable from a
// floating yellow pill (DEBUG only) or with `--home-variant <0|A|B|C>`. Lives on branch
// prototype/home-redesign only; the winning variant gets rewritten properly in the real issue.
#if DEBUG
import SwiftUI

enum HomePrototypeVariant: String, CaseIterable {
    case current = "0"
    case a = "A"
    case b = "B"
    case c = "C"

    var name: String {
        switch self {
        case .current: "Current Home"
        case .a: "Launchpad"
        case .b: "Up Next"
        case .c: "Bottom Dock"
        }
    }

    var next: Self {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    var previous: Self {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + all.count - 1) % all.count]
    }
}

struct HomePrototypeSwitcher: View {
    @Binding var variant: HomePrototypeVariant

    var body: some View {
        HStack(spacing: 10) {
            Button { variant = variant.previous } label: {
                Image(systemName: "chevron.left").frame(width: 24, height: 24)
            }
            Text("\(variant.rawValue) · \(variant.name)")
                .font(.caption.monospaced().weight(.bold))
            Button { variant = variant.next } label: {
                Image(systemName: "chevron.right").frame(width: 24, height: 24)
            }
        }
        .font(.caption.weight(.heavy))
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.yellow, in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }
}

// MARK: - Derived data

struct HomePrototypeModel {
    struct QuickStart: Identifiable {
        let session: WorkoutSession
        let lastDone: String
        let exerciseNames: [String]

        var id: UUID { session.id }
        var title: String { session.title }
    }

    struct Day: Identifiable {
        let date: Date
        let hasWorkout: Bool
        let isToday: Bool
        let isFuture: Bool

        var id: Date { date }
    }

    struct Week: Identifiable {
        let start: Date
        let days: [Day]
        let count: Int
        let isCurrent: Bool

        var id: Date { start }
    }

    let quickStarts: [QuickStart]
    let upNext: QuickStart?
    let weeks: [Week]
    let headline: String
    let subheadline: String
    let thisWeekCount: Int
    let lastWeekCount: Int
    let averagePerWeek: Double

    init(content: HomeContent, now: Date, weekCount: Int = 12, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)

        func daysAgo(_ date: Date) -> Int {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: today).day ?? 0
        }

        func relative(_ date: Date) -> String {
            let days = daysAgo(date)
            switch days {
            case ...0: return "Today"
            case 1: return "Yesterday"
            case 2..<14: return "\(days) days ago"
            default: return "\(days / 7) weeks ago"
            }
        }

        var seenTitles = Set<String>()
        var quickStarts: [QuickStart] = []
        for session in content.completedSessions where quickStarts.count < 4 {
            let key = session.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, seenTitles.insert(key).inserted else { continue }
            quickStarts.append(QuickStart(
                session: session,
                lastDone: relative(session.startedAt),
                exerciseNames: session.sortedLoggedExercises.map(\.exerciseSnapshotName)
            ))
        }
        self.quickStarts = quickStarts
        // Rotation guess: of the workouts done in the last three weeks, the one done longest ago.
        upNext = quickStarts.filter { daysAgo($0.session.startedAt) <= 21 }.last ?? quickStarts.first

        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        weeks = (0..<weekCount).reversed().compactMap { weeksBack in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: currentWeekStart),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
            let sessions = content.completedSessions.filter { $0.startedAt >= start && $0.startedAt < end }
            let days = (0..<7).compactMap { offset -> Day? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
                return Day(
                    date: date,
                    hasWorkout: sessions.contains { calendar.isDate($0.startedAt, inSameDayAs: date) },
                    isToday: calendar.isDate(date, inSameDayAs: now),
                    isFuture: date > today
                )
            }
            return Week(start: start, days: days, count: sessions.count, isCurrent: weeksBack == 0)
        }

        thisWeekCount = weeks.last?.count ?? 0
        lastWeekCount = weeks.dropLast().last?.count ?? 0
        let pastWeeks = weeks.dropLast()
        averagePerWeek = pastWeeks.isEmpty
            ? 0
            : Double(pastWeeks.reduce(0) { $0 + $1.count }) / Double(pastWeeks.count)

        // Neutral headline: today's date only — no "days since" nudge.
        headline = now.formatted(.dateTime.weekday(.wide))
        subheadline = now.formatted(.dateTime.month(.wide).day())
    }

    static func topSet(_ loggedExercise: LoggedExercise, unit: MeasurementUnit) -> String? {
        let best = loggedExercise.sortedSets.filter(\.isCompleted).max { lhs, rhs in
            let l = (WorkoutNumericInputPolicy.validatedWeight(lhs.weight) ?? 0, lhs.reps ?? 0)
            let r = (WorkoutNumericInputPolicy.validatedWeight(rhs.weight) ?? 0, rhs.reps ?? 0)
            return l < r
        }
        guard let best, let reps = WorkoutNumericInputPolicy.validatedReps(best.reps) else { return nil }
        if let weight = unit.displayWeight(fromCanonicalPounds: WorkoutNumericInputPolicy.validatedWeight(best.weight)),
           weight > 0 {
            return "\(WorkoutFormatters.number(weight)) \(unit == .pounds ? "lb" : "kg") × \(reps)"
        }
        return "\(reps) reps"
    }
}

struct HomePrototypeActions {
    let primary: () -> Void
    let quickStart: (WorkoutSession) -> Void
    let openWorkout: (WorkoutSession) -> Void
    let browseAll: () -> Void
}

// MARK: - Small shared pieces

private struct HomePrototypeEyebrow: View {
    let now: Date

    var body: some View {
        // Date moved into the headline; keep a little top spacing for the switcher pill.
        Color.clear.frame(height: 12)
    }
}

private struct HomePrototypeSolidButton: View {
    let presentation: HomePrimaryWorkoutPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: presentation.isActive ? "figure.strengthtraining.traditional" : "plus")
                    .font(.title3.weight(.bold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.18), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.title3.weight(.bold))
                    if let detail = presentation.detail {
                        Text(detail)
                            .font(.subheadline.weight(.semibold))
                            .opacity(0.85)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(AppTheme.onBrandAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(AppTheme.brandAccentGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: AppTheme.brandAccentGlow, radius: 14, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
    }
}

private struct HomePrototypeSectionTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 2)
    }
}

/// Last Workout with each exercise's best set instead of a set count.
private struct HomePrototypeLastWorkoutCard: View {
    let session: WorkoutSession
    let unit: MeasurementUnit
    let open: () -> Void

    var body: some View {
        let exercises = session.sortedLoggedExercises
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HomePrototypeSectionTitle(title: "Last Workout")

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.title)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text(
                                    "\(WorkoutFormatters.compactDate(session.startedAt)) · "
                                        + "\(AppTheme.formatDuration(WorkoutMetrics(session: session).durationSeconds)) · "
                                        + "\(WorkoutMetrics(session: session).completedSetCount) sets"
                                )
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textTertiary)
                        }

                        Divider()

                        HStack {
                            Text("EXERCISE")
                            Spacer()
                            Text("BEST SET")
                        }
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(AppTheme.textTertiary)

                        ForEach(exercises.prefix(4)) { loggedExercise in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(loggedExercise.exerciseSnapshotName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(HomePrototypeModel.topSet(loggedExercise, unit: unit) ?? "—")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(AppTheme.textPrimary)
                            }
                        }

                        if exercises.count > 4 {
                            Text("+ \(exercises.count - 4) more")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.brandAccentForeground)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Variant A — Launchpad: solid action, horizontal repeat cards, 12-week dot grid

struct HomePrototypeVariantA: View {
    let model: HomePrototypeModel
    let content: HomeContent
    let primary: HomePrimaryWorkoutPresentation
    let unit: MeasurementUnit
    let now: Date
    let actions: HomePrototypeActions

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HomePrototypeEyebrow(now: now)

                Text(model.headline)
                    .font(.title.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.top, 3)
                Text(model.subheadline)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.top, 3)
                    .padding(.bottom, 18)

                SignedOutReminderBanner(bottomSpacing: 18)

                HomePrototypeSolidButton(presentation: primary, action: actions.primary)

                if !primary.isActive, !model.quickStarts.isEmpty {
                    HomePrototypeSectionTitle(title: "Repeat a Workout")
                        .padding(.top, 28)
                        .padding(.bottom, 10)
                    repeatCards
                }

                VStack(alignment: .leading, spacing: 10) {
                    HomePrototypeSectionTitle(title: "Last 12 Weeks")
                    SurfaceCard(padding: 16) {
                        VStack(spacing: 16) {
                            dotGrid
                            HStack {
                                stat(value: "\(model.thisWeekCount)", label: "This week")
                                stat(value: "\(model.lastWeekCount)", label: "Last week")
                                stat(value: WorkoutFormatters.number((model.averagePerWeek * 10).rounded() / 10), label: "Avg / week")
                            }
                        }
                    }
                }
                .padding(.top, 28)

                if let lastWorkout = content.lastWorkout {
                    HomePrototypeLastWorkoutCard(session: lastWorkout, unit: unit) {
                        actions.openWorkout(lastWorkout)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 12)
                }
            }
            .padding(AppTheme.shellPadding)
        }
    }

    private var repeatCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.quickStarts) { quickStart in
                    Button { actions.quickStart(quickStart.session) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(quickStart.title)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.brandAccentForeground)
                            }
                            Text(quickStart.lastDone)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.brandAccentForeground)
                            Text(quickStart.exerciseNames.prefix(3).joined(separator: "\n"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(3)
                                .padding(.top, 2)
                        }
                        .padding(14)
                        .frame(width: 168, height: 128, alignment: .topLeading)
                        .background(AppTheme.groupedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(AppTheme.subtleBorder))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: actions.browseAll) {
                    VStack(spacing: 8) {
                        Image(systemName: "square.stack")
                            .font(.title3.weight(.semibold))
                        Text("All Workouts")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .frame(width: 112, height: 128)
                    .background(AppTheme.brandAccentMuted, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .contentMargins(.horizontal, AppTheme.shellPadding, for: .scrollContent)
        .padding(.horizontal, -AppTheme.shellPadding)
    }

    private var dotGrid: some View {
        HStack(spacing: 4) {
            ForEach(model.weeks) { week in
                VStack(spacing: 4) {
                    ForEach(week.days) { day in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(day.hasWorkout ? AppTheme.brandAccentFill : (day.isFuture ? Color.clear : AppTheme.recessedSurface))
                            .overlay {
                                if day.isToday {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(AppTheme.brandAccentForeground, lineWidth: 2)
                                } else if day.isFuture {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(AppTheme.subtleBorder)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Variant B — Up Next: rotation-aware hero, rotation list, weekly bar chart

struct HomePrototypeVariantB: View {
    let model: HomePrototypeModel
    let content: HomeContent
    let primary: HomePrimaryWorkoutPresentation
    let unit: MeasurementUnit
    let now: Date
    let actions: HomePrototypeActions

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HomePrototypeEyebrow(now: now)

                Text(model.headline)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.top, 3)
                    .padding(.bottom, 18)

                SignedOutReminderBanner(bottomSpacing: 18)

                if primary.isActive {
                    HomePrototypeSolidButton(presentation: primary, action: actions.primary)
                } else if let upNext = model.upNext {
                    hero(upNext)
                } else {
                    HomePrototypeSolidButton(presentation: primary, action: actions.primary)
                }

                let others = model.quickStarts.filter { $0.id != model.upNext?.id }
                if !primary.isActive, !others.isEmpty {
                    HomePrototypeSectionTitle(title: "Your Rotation")
                        .padding(.top, 28)
                        .padding(.bottom, 10)
                    SurfaceCard(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(others.enumerated()), id: \.element.id) { index, quickStart in
                                if index > 0 { Divider().padding(.leading, 16) }
                                Button { actions.quickStart(quickStart.session) } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(quickStart.title)
                                                .font(.headline)
                                                .foregroundStyle(AppTheme.textPrimary)
                                            Text("\(quickStart.lastDone) · \(quickStart.exerciseNames.count) exercises")
                                                .font(.footnote.weight(.medium))
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "play.circle.fill")
                                            .font(.title)
                                            .foregroundStyle(AppTheme.brandAccentForeground)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HomePrototypeSectionTitle(
                        title: "Workouts per Week",
                        trailing: "avg \(WorkoutFormatters.number((model.averagePerWeek * 10).rounded() / 10))"
                    )
                    SurfaceCard(padding: 16) { barChart }
                }
                .padding(.top, 28)

                if let lastWorkout = content.lastWorkout {
                    compactLastWorkout(lastWorkout)
                        .padding(.top, 28)
                        .padding(.bottom, 12)
                }
            }
            .padding(AppTheme.shellPadding)
        }
    }

    private func hero(_ upNext: HomePrototypeModel.QuickStart) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("UP NEXT")
                .font(.caption.weight(.heavy))
                .tracking(1.2)
                .opacity(0.8)
            Text(upNext.title)
                .font(.system(size: 38, weight: .heavy))
                .padding(.top, 2)
            Text("Last done \(upNext.lastDone.lowercased()) · \(upNext.exerciseNames.count) exercises")
                .font(.subheadline.weight(.semibold))
                .opacity(0.85)
            Text(upNext.exerciseNames.joined(separator: " · "))
                .font(.footnote.weight(.medium))
                .opacity(0.7)
                .lineLimit(2)
                .padding(.top, 10)

            HStack(spacing: 10) {
                Button { actions.quickStart(upNext.session) } label: {
                    Label("Start \(upNext.title)", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.brandAccentFill)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: actions.browseAll) {
                    Label("Other", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.18), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)
        }
        .foregroundStyle(AppTheme.onBrandAccent)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.brandAccentGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: AppTheme.brandAccentGlow, radius: 16, y: 8)
    }

    private var barChart: some View {
        let maxCount = max(3, model.weeks.map(\.count).max() ?? 0)
        return VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(model.weeks) { week in
                    VStack(spacing: 4) {
                        if week.count > 0 {
                            Text("\(week.count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(week.isCurrent ? AppTheme.brandAccentForeground : AppTheme.textSecondary)
                        }
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(week.count == 0 ? AppTheme.recessedSurface : AppTheme.brandAccentFill)
                            .opacity(week.isCurrent && week.count > 0 ? 0.65 : 1)
                            .overlay {
                                if week.isCurrent {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(AppTheme.brandAccentForeground, lineWidth: 2)
                                }
                            }
                            .frame(height: week.count == 0 ? 6 : CGFloat(week.count) / CGFloat(maxCount) * 90)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 112, alignment: .bottom)

            HStack {
                Text(model.weeks.first.map { $0.start.formatted(.dateTime.month(.abbreviated).day()) } ?? "")
                Spacer()
                Text("This week")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func compactLastWorkout(_ session: WorkoutSession) -> some View {
        Button { actions.openWorkout(session) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HomePrototypeSectionTitle(title: "Last Workout", trailing: WorkoutFormatters.compactDate(session.startedAt))
                SurfaceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(session.title).font(.headline).foregroundStyle(AppTheme.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textTertiary)
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 10) {
                            ForEach(session.sortedLoggedExercises.prefix(4)) { loggedExercise in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(HomePrototypeModel.topSet(loggedExercise, unit: unit) ?? "—")
                                        .font(.subheadline.weight(.bold))
                                        .monospacedDigit()
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Text(loggedExercise.exerciseSnapshotName)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Variant C — Bottom Dock: calendar rows up top, thumb-reach action + repeat chips docked

struct HomePrototypeVariantC: View {
    let model: HomePrototypeModel
    let content: HomeContent
    let primary: HomePrimaryWorkoutPresentation
    let unit: MeasurementUnit
    let now: Date
    let actions: HomePrototypeActions

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HomePrototypeEyebrow(now: now)

                Text(model.headline)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.top, 3)
                Text(model.subheadline)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.top, 4)
                    .padding(.bottom, 22)

                SignedOutReminderBanner(bottomSpacing: 18)

                SurfaceCard(padding: 16) { calendarRows }

                if let lastWorkout = content.lastWorkout {
                    HomePrototypeLastWorkoutCard(session: lastWorkout, unit: unit) {
                        actions.openWorkout(lastWorkout)
                    }
                    .padding(.top, 28)
                }
            }
            .padding(AppTheme.shellPadding)
            .padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { dock }
    }

    private var calendarRows: some View {
        let recentWeeks = model.weeks.suffix(6)
        return VStack(spacing: 10) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 50, height: 1)
                ForEach(recentWeeks.last?.days ?? []) { day in
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .frame(maxWidth: .infinity)
                }
                Color.clear.frame(width: 26, height: 1)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppTheme.textTertiary)

            ForEach(recentWeeks) { week in
                HStack(spacing: 0) {
                    Text(week.isCurrent ? "This wk" : week.start.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(week.isCurrent ? AppTheme.brandAccentForeground : AppTheme.textTertiary)
                        .frame(width: 50, alignment: .leading)
                    ForEach(week.days) { day in
                        Circle()
                            .fill(day.hasWorkout ? AppTheme.brandAccentFill : (day.isFuture ? Color.clear : AppTheme.recessedSurface))
                            .overlay {
                                if day.isToday {
                                    Circle().strokeBorder(AppTheme.brandAccentForeground, lineWidth: 2)
                                } else if day.isFuture {
                                    Circle().strokeBorder(AppTheme.subtleBorder)
                                }
                            }
                            .overlay {
                                if day.hasWorkout {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.weight(.heavy))
                                        .foregroundStyle(AppTheme.onBrandAccent)
                                }
                            }
                            .frame(width: 28, height: 28)
                            .frame(maxWidth: .infinity)
                    }
                    Text("\(week.count)")
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(week.count > 0 ? AppTheme.textPrimary : AppTheme.textTertiary)
                        .frame(width: 26, alignment: .trailing)
                }
            }
        }
    }

    private var dock: some View {
        VStack(spacing: 10) {
            if !primary.isActive, !model.quickStarts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.quickStarts) { quickStart in
                            Button { actions.quickStart(quickStart.session) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(AppTheme.brandAccentForeground)
                                    Text(quickStart.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                    Text(quickStart.lastDone)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(AppTheme.groupedSurface, in: Capsule())
                                .overlay(Capsule().strokeBorder(AppTheme.subtleBorder))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .contentMargins(.horizontal, AppTheme.shellPadding, for: .scrollContent)
            }

            HomePrototypeSolidButton(presentation: primary, action: actions.primary)
                .padding(.horizontal, AppTheme.shellPadding)
        }
        .padding(.top, 18)
        .padding(.bottom, 8)
        .background {
            LinearGradient(
                stops: [
                    .init(color: AppTheme.canvasBackground.opacity(0), location: 0),
                    .init(color: AppTheme.canvasBackground, location: 0.12),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }
}
#endif
