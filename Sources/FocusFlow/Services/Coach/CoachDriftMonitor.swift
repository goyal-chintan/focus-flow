import Foundation

/// How far off track the user is outside a focus block (rescue loop design §1).
enum DriftLevel: Int, Comparable, CaseIterable, Sendable, Codable {
    /// L0: nothing notable.
    case ok = 0
    /// L1: drifting.
    case drifting = 1
    /// L2: lost.
    case lost = 2
    /// L3: spiral.
    case spiral = 3

    static func < (lhs: DriftLevel, rhs: DriftLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .ok: "OK"
        case .drifting: "Check-in"
        case .lost: "Reset"
        case .spiral: "Rescue"
        }
    }
}

/// What the frontmost context counted as for one tracking tick.
enum DriftSampleKind: Equatable, Sendable {
    /// A real derailer (YouTube, X, Netflix, zee5…). Never a work tool.
    case derailer(name: String)
    /// Work or neutral context that counts as pseudo-work under the pseudo rules.
    case pseudo(name: String)
    /// Anything else: on-track work, FocusFlow itself, system UI, an away user.
    case other

    var name: String? {
        switch self {
        case .derailer(let name), .pseudo(let name): name
        case .other: nil
        }
    }
}

/// The main reason behind the current level, used to word the honest fact.
enum DriftSignal: Equatable, Sendable {
    case derailer(name: String, minutes: Int)
    case pseudo(name: String, minutes: Int)
    case hopping
}

/// Output of `DriftMonitor.assess`.
struct DriftAssessment: Equatable, Sendable {
    /// The monitor runs: no session, and inside a learned window or pacing pressure ≥ 0.5.
    let isActive: Bool
    let level: DriftLevel
    /// Level from usage alone, before ignored rescues raised it.
    let baseLevel: DriftLevel
    /// Derailer minutes in the last 30 minutes (since the window opened or the last block ended).
    let derailerRecentMinutes: Int
    /// Derailer minutes since the window opened (or the last block ended).
    let derailerWindowMinutes: Int
    /// Pseudo-work minutes in the pseudo lookback (since the window opened or the last block ended).
    let pseudoMinutes: Int
    let isHopping: Bool
    let ignoredRescues: Int
    /// The derailer with the most minutes since the window opened.
    let topDerailer: (name: String, minutes: Int)?
    /// The pseudo-work context with the most minutes in the lookback.
    let topPseudo: (name: String, minutes: Int)?
    let windowStart: Date

    static func inactive(windowStart: Date) -> DriftAssessment {
        DriftAssessment(
            isActive: false, level: .ok, baseLevel: .ok, derailerRecentMinutes: 0, derailerWindowMinutes: 0,
            pseudoMinutes: 0, isHopping: false, ignoredRescues: 0, topDerailer: nil, topPseudo: nil,
            windowStart: windowStart
        )
    }

    /// Strongest reason for the level: derailer time first, then pseudo-work, then hopping.
    var dominantSignal: DriftSignal? {
        guard level > .ok else { return nil }
        if let topDerailer, topDerailer.minutes > 0,
           derailerRecentMinutes >= DriftMonitor.derailerMinutesForDrifting || topDerailer.minutes >= (topPseudo?.minutes ?? 0) {
            return .derailer(name: topDerailer.name, minutes: topDerailer.minutes)
        }
        if let topPseudo, topPseudo.minutes > 0 {
            return .pseudo(name: topPseudo.name, minutes: pseudoMinutes)
        }
        if isHopping { return .hopping }
        if let topDerailer { return .derailer(name: topDerailer.name, minutes: topDerailer.minutes) }
        return nil
    }

    /// Minutes the ambient counter shows: the derailer's window time when a derailer leads,
    /// otherwise all drift time (derailer + pseudo-work).
    var ambientMinutes: Int {
        if case .derailer(_, let minutes) = dominantSignal { return minutes }
        return derailerWindowMinutes + pseudoMinutes
    }

    static func == (lhs: DriftAssessment, rhs: DriftAssessment) -> Bool {
        lhs.isActive == rhs.isActive && lhs.level == rhs.level && lhs.baseLevel == rhs.baseLevel
            && lhs.derailerRecentMinutes == rhs.derailerRecentMinutes
            && lhs.derailerWindowMinutes == rhs.derailerWindowMinutes
            && lhs.pseudoMinutes == rhs.pseudoMinutes && lhs.isHopping == rhs.isHopping
            && lhs.ignoredRescues == rhs.ignoredRescues
            && lhs.topDerailer?.name == rhs.topDerailer?.name && lhs.topDerailer?.minutes == rhs.topDerailer?.minutes
            && lhs.topPseudo?.name == rhs.topPseudo?.name && lhs.topPseudo?.minutes == rhs.topPseudo?.minutes
            && lhs.windowStart == rhs.windowStart
    }
}

/// Rolling drift detector (rescue loop design §1). Pure: the caller feeds one sample per
/// tracking tick and asks for an assessment; nothing here reads the clock or the store.
///
/// Signals and thresholds (all named constants, unit-tested):
/// - **Derailer time**: frontmost classified a derailer by `DerailerClassifier` (work tools such
///   as Slack, Cursor, Claude, Arc, Atlassian and GitHub never count).
/// - **Pseudo-work time**: work/neutral contexts with no session while pacing pressure ≥ 0.5,
///   plus contexts the user has rated busywork ("side quest") before. The design's L2 bar
///   (40 min) cannot fit a 30-minute window, so pseudo-work uses a 60-minute lookback.
/// - **Hopping**: ≥ 6 app switches/min sustained for 3 minutes.
/// - **Ignored rescues**: L1 + 1 ignored → L2; L2 + 2 ignored → L3.
///
/// Every count starts at the later of the window start and the end of the last focus block,
/// so a block resets the slate.
struct DriftMonitor: Sendable {
    // MARK: Thresholds

    static let derailerLookback: TimeInterval = 30 * 60
    static let pseudoLookback: TimeInterval = 60 * 60
    static let derailerMinutesForDrifting = 10
    static let derailerMinutesForLost = 20
    /// L3 counts derailer minutes over the whole window, not the 30-minute lookback.
    static let derailerWindowMinutesForSpiral = 40
    static let pseudoMinutesForDrifting = 20
    static let pseudoMinutesForLost = 40
    static let hoppingSwitchesPerMinute = 6.0
    static let hoppingSustain: TimeInterval = 3 * 60
    static let ignoredRescuesForLost = 1
    static let ignoredRescuesForSpiral = 2
    /// The monitor only runs inside a learned window, or outside one when pacing pressure is at least this.
    static let pacingPressureForActivation = 0.5
    /// Pseudo-work only accrues while pacing pressure is at least this (or the context is known busywork).
    static let pacingPressureForPseudoWork = 0.5
    /// How long samples are kept (longest learned window plus margin).
    static let retention: TimeInterval = 8 * 60 * 60
    /// Samples of the same kind closer than this merge into one bucket.
    static let bucketSeconds: TimeInterval = 60

    struct Sample: Equatable, Sendable {
        var at: Date
        var seconds: Int
        var kind: DriftSampleKind
    }

    struct Context: Sendable {
        var now: Date
        var sessionActive: Bool
        var inLearnedWindow: Bool
        /// Today's pacing pressure (`CoachGoalPacing.pressure`); nil when unknown.
        var pacingPressure: Double?
        /// Start of the current focus window (`CoachFocusWindow`).
        var windowStart: Date
        /// End of the last focus block; counts start after it.
        var lastSessionEnd: Date?
        var ignoredRescues: Int = 0
    }

    private(set) var samples: [Sample] = []
    private(set) var hopReadings: [(at: Date, rate: Double)] = []

    init() {}

    // MARK: Feeding

    /// Records `seconds` of the frontmost context, and the current app-switch rate.
    mutating func record(at now: Date, seconds: Int, kind: DriftSampleKind, switchesPerMinute: Double) {
        hopReadings.append((now, switchesPerMinute))
        hopReadings.removeAll { now.timeIntervalSince($0.at) > Self.hoppingSustain * 2 }
        guard seconds > 0 else { return }
        if var last = samples.last, last.kind == kind, now.timeIntervalSince(last.at) < Self.bucketSeconds,
           now >= last.at {
            last.seconds += seconds
            samples[samples.count - 1] = last
        } else {
            samples.append(Sample(at: now, seconds: seconds, kind: kind))
        }
        let cutoff = now.addingTimeInterval(-Self.retention)
        if let first = samples.first, first.at < cutoff {
            samples.removeAll { $0.at < cutoff }
        }
    }

    /// A focus block started: drift is over.
    mutating func reset() {
        samples.removeAll()
        hopReadings.removeAll()
    }

    // MARK: Activation

    /// No session, and inside a learned window or pacing pressure ≥ 0.5.
    static func isActive(sessionActive: Bool, inLearnedWindow: Bool, pacingPressure: Double?) -> Bool {
        guard !sessionActive else { return false }
        return inLearnedWindow || (pacingPressure ?? 0) >= pacingPressureForActivation
    }

    // MARK: Assessment

    func assess(_ context: Context) -> DriftAssessment {
        guard Self.isActive(
            sessionActive: context.sessionActive,
            inLearnedWindow: context.inLearnedWindow,
            pacingPressure: context.pacingPressure
        ) else { return .inactive(windowStart: context.windowStart) }

        let floor = max(context.windowStart, context.lastSessionEnd ?? .distantPast)
        let now = context.now
        let derailerRecentStart = max(floor, now.addingTimeInterval(-Self.derailerLookback))
        let pseudoStart = max(floor, now.addingTimeInterval(-Self.pseudoLookback))

        var derailerRecent = 0
        var derailerWindow = 0
        var pseudo = 0
        var derailerByName: [String: (name: String, seconds: Int)] = [:]
        var pseudoByName: [String: (name: String, seconds: Int)] = [:]
        for sample in samples where sample.at > floor && sample.at <= now {
            switch sample.kind {
            case .derailer(let name):
                derailerWindow += sample.seconds
                derailerByName[name.lowercased(), default: (name, 0)].seconds += sample.seconds
                if sample.at > derailerRecentStart { derailerRecent += sample.seconds }
            case .pseudo(let name):
                if sample.at > pseudoStart {
                    pseudo += sample.seconds
                    pseudoByName[name.lowercased(), default: (name, 0)].seconds += sample.seconds
                }
            case .other:
                break
            }
        }

        let hopping = Self.isHopping(hopReadings, now: now, since: floor)
        let derailerRecentMinutes = derailerRecent / 60
        let derailerWindowMinutes = derailerWindow / 60
        let pseudoMinutes = pseudo / 60
        let base = Self.baseLevel(
            derailerRecentMinutes: derailerRecentMinutes,
            derailerWindowMinutes: derailerWindowMinutes,
            pseudoMinutes: pseudoMinutes,
            hopping: hopping
        )
        let level = Self.level(base: base, ignoredRescues: context.ignoredRescues)
        let topDerailer = derailerByName.values.max { $0.seconds < $1.seconds }.map { ($0.name, $0.seconds / 60) }
        let topPseudo = pseudoByName.values.max { $0.seconds < $1.seconds }.map { ($0.name, $0.seconds / 60) }
        return DriftAssessment(
            isActive: true,
            level: level,
            baseLevel: base,
            derailerRecentMinutes: derailerRecentMinutes,
            derailerWindowMinutes: derailerWindowMinutes,
            pseudoMinutes: pseudoMinutes,
            isHopping: hopping,
            ignoredRescues: context.ignoredRescues,
            topDerailer: topDerailer,
            topPseudo: topPseudo,
            windowStart: context.windowStart
        )
    }

    /// Level from usage alone (design §1 table).
    static func baseLevel(derailerRecentMinutes: Int, derailerWindowMinutes: Int, pseudoMinutes: Int, hopping: Bool) -> DriftLevel {
        if derailerWindowMinutes >= derailerWindowMinutesForSpiral { return .spiral }
        if derailerRecentMinutes >= derailerMinutesForLost || pseudoMinutes >= pseudoMinutesForLost { return .lost }
        if derailerRecentMinutes >= derailerMinutesForDrifting || pseudoMinutes >= pseudoMinutesForDrifting || hopping {
            return .drifting
        }
        return .ok
    }

    /// Ignored rescues raise the level: L1 + 1 ignored → L2, L2 + 2 ignored → L3.
    /// They never create drift on their own (L0 stays L0).
    static func level(base: DriftLevel, ignoredRescues: Int) -> DriftLevel {
        guard base > .ok else { return .ok }
        var level = base
        if level == .drifting && ignoredRescues >= ignoredRescuesForLost { level = .lost }
        if level == .lost && ignoredRescues >= ignoredRescuesForSpiral { level = .spiral }
        return level
    }

    /// ≥ 6 switches/min in every reading of the last 3 minutes, with readings covering them.
    static func isHopping(_ readings: [(at: Date, rate: Double)], now: Date, since floor: Date) -> Bool {
        let start = now.addingTimeInterval(-hoppingSustain)
        guard start >= floor else { return false }
        let recent = readings.filter { $0.at >= start && $0.at <= now }
        guard let earliest = recent.map(\.at).min(),
              earliest.timeIntervalSince(start) <= 30 else { return false }
        return recent.allSatisfy { $0.rate >= hoppingSwitchesPerMinute }
    }

    // MARK: Classification

    /// Classifies the frontmost context for one tick. Reuses `DerailerClassifier`, so work tools
    /// (Slack, Cursor, Claude, Arc, Atlassian, GitHub, …) are never derailers; they can only be
    /// pseudo-work, and only while pacing pressure ≥ 0.5 or the context is known busywork.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: frontmost app; nil for FocusFlow itself or system UI (→ `.other`).
    ///   - browserHost: normalized host when domain collection is on.
    ///   - category: the tracker's category (`AppUsageEntry.classify` + user rules).
    ///   - userAway: no keyboard/mouse input for a while; only a derailer (video) still counts.
    static func classify(
        bundleIdentifier: String?,
        appName: String?,
        browserHost: String?,
        displayName: String?,
        category: AppUsageEntry.AppCategory,
        confirmedKeys: Set<String> = [],
        allowedKeys: Set<String> = [],
        pacingPressure: Double?,
        busyworkContexts: Set<String> = [],
        userAway: Bool = false
    ) -> DriftSampleKind {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return .other }
        let usage: UsageSample
        if let browserHost, !browserHost.isEmpty {
            usage = UsageSample(day: .distantPast, appName: displayName ?? browserHost, bundleIdentifier: "domain:\(browserHost)", outsideFocusSeconds: 1)
        } else {
            usage = UsageSample(day: .distantPast, appName: appName ?? displayName ?? bundleIdentifier, bundleIdentifier: bundleIdentifier, outsideFocusSeconds: 1)
        }
        if DerailerClassifier.isSystemProcess(usage) { return .other }
        let name = Self.contextName(displayName: displayName, usage: usage)
        if DerailerClassifier.isDerailer(usage, confirmedKeys: confirmedKeys, allowedKeys: allowedKeys) {
            return .derailer(name: name)
        }
        guard !userAway else { return .other }
        // A browser without a known host is ambiguous: count it as pseudo-work like any work context.
        let isWorkOrNeutral = DerailerClassifier.isWorkTool(usage) || category != .distracting
        guard isWorkOrNeutral else { return .other }
        let knownBusywork = busyworkContexts.contains(name.lowercased())
        if knownBusywork || (pacingPressure ?? 0) >= pacingPressureForPseudoWork {
            return .pseudo(name: name)
        }
        return .other
    }

    static func contextName(displayName: String?, usage: UsageSample) -> String {
        if let displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
            return displayName
        }
        return DerailerClassifier.displayName(of: usage)
    }
}

/// The focus window the rescue loop is working in: the contiguous run of good hours around
/// `now` (learned windows), or, when the monitor is active only because pacing pressure is high,
/// the whole day so far. "Once per window" and the ambient counter key off `start`.
struct CoachFocusWindow: Equatable, Sendable {
    let start: Date
    /// True when `now` is inside a learned (or cold-start) good window.
    let isLearned: Bool

    /// Hour label for copy ("22:00"), only for learned windows.
    func hourLabel(calendar: Calendar = .current) -> String? {
        guard isLearned else { return nil }
        let hour = calendar.component(.hour, from: start)
        return String(format: "%02d:00", hour)
    }

    static func current(now: Date, model: CoachAvailabilityModel, calendar: Calendar = .current) -> CoachFocusWindow {
        let dayStart = calendar.startOfDay(for: now)
        let learned = model.mode != .noData && model.isGoodWindow(now)
        guard learned, var hourStart = calendar.dateInterval(of: .hour, for: now)?.start else {
            // No data (every hour is "good") or pacing-only activation: the day so far is the window.
            return CoachFocusWindow(start: dayStart, isLearned: false)
        }
        // Walk back over contiguous good hours, at most to the start of today.
        while hourStart > dayStart,
              let previous = calendar.date(byAdding: .hour, value: -1, to: hourStart),
              model.isGoodWindow(previous) {
            hourStart = previous
        }
        return CoachFocusWindow(start: hourStart, isLearned: true)
    }
}
