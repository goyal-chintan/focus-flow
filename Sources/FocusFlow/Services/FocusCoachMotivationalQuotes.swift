import Foundation

// MARK: - Quote model

struct FocusCoachQuote: Sendable {
    let text: String
    let attribution: String
    let category: Category

    enum Category: String, CaseIterable, Sendable {
        case procrastination
        case distraction
        case priority        // for "low-priority work" / productive-procrastination pattern
        case timeUrgency
        case momentum
    }
}

// MARK: - Quote bank

enum FocusCoachMotivationalQuotes {

    static let all: [FocusCoachQuote] =
        procrastination + distraction + priority + timeUrgency + momentum

    // MARK: Procrastination (5)
    static let procrastination: [FocusCoachQuote] = [
        .init(
            text: "You may delay, but time will not.",
            attribution: "Benjamin Franklin",
            category: .procrastination
        ),
        .init(
            text: "A year from now you may wish you had started today.",
            attribution: "Karen Lamb",
            category: .procrastination
        ),
        .init(
            text: "The most pernicious aspect of procrastination is that it can become a habit.",
            attribution: "Robert McKain",
            category: .procrastination
        ),
        .init(
            text: "In a moment of decision, the best thing you can do is the right thing. The worst thing you can do is nothing.",
            attribution: "Theodore Roosevelt",
            category: .procrastination
        ),
        .init(
            text: "You don't have to be great to start, but you have to start to be great.",
            attribution: "Zig Ziglar",
            category: .procrastination
        ),
    ]

    // MARK: Distraction (4)
    static let distraction: [FocusCoachQuote] = [
        .init(
            text: "Every time you check your phone, you reset the 23-minute clock it takes to recover deep focus.",
            attribution: "Gloria Mark",
            category: .distraction
        ),
        .init(
            text: "Your attention is your most precious resource. Guard it fiercely.",
            attribution: "Naval Ravikant",
            category: .distraction
        ),
        .init(
            text: "The ability to concentrate is one of the most important skills of the digital age.",
            attribution: "Cal Newport",
            category: .distraction
        ),
        .init(
            text: "Distraction is the enemy of vision.",
            attribution: "Terri Guillemets",
            category: .distraction
        ),
    ]

    // MARK: Priority — for "low-priority work" / vibe-coding / over-planning pattern (4)
    static let priority: [FocusCoachQuote] = [
        .init(
            text: "What is important is seldom urgent. What is urgent is seldom important.",
            attribution: "Dwight D. Eisenhower",
            category: .priority
        ),
        .init(
            text: "Saying yes to too many shallow things means saying no to the deep things that matter.",
            attribution: "Cal Newport",
            category: .priority
        ),
        .init(
            text: "The key is not to prioritize your schedule, but to schedule your priorities.",
            attribution: "Stephen Covey",
            category: .priority
        ),
        .init(
            text: "You can do anything, but not everything.",
            attribution: "David Allen",
            category: .priority
        ),
    ]

    // MARK: Time Urgency (4)
    static let timeUrgency: [FocusCoachQuote] = [
        .init(
            text: "Time is the scarcest resource. Unless managed, nothing else can be managed.",
            attribution: "Peter Drucker",
            category: .timeUrgency
        ),
        .init(
            text: "Either you run the day or the day runs you.",
            attribution: "Jim Rohn",
            category: .timeUrgency
        ),
        .init(
            text: "You will never 'find' time for anything. You must make it.",
            attribution: "Charles Buxton",
            category: .timeUrgency
        ),
        .init(
            text: "Lost time is never found again.",
            attribution: "Benjamin Franklin",
            category: .timeUrgency
        ),
    ]

    // MARK: Momentum (3)
    static let momentum: [FocusCoachQuote] = [
        .init(
            text: "The secret of getting ahead is getting started.",
            attribution: "Mark Twain",
            category: .momentum
        ),
        .init(
            text: "Action is the foundational key to all success.",
            attribution: "Pablo Picasso",
            category: .momentum
        ),
        .init(
            text: "The best time to start was yesterday. The next best time is now.",
            attribution: "Unknown",
            category: .momentum
        ),
    ]

    // MARK: - Selection

    /// Deterministically selects a quote from the given category.
    /// Stable within a day (uses the day-of-era ordinal), feels fresh each morning.
    /// `seed` can be the today session count to vary across sessions on the same day.
    static func pick(
        category: FocusCoachQuote.Category,
        seed: Int = 0
    ) -> FocusCoachQuote {
        let pool: [FocusCoachQuote]
        switch category {
        case .procrastination: pool = procrastination
        case .distraction:     pool = distraction
        case .priority:        pool = priority
        case .timeUrgency:     pool = timeUrgency
        case .momentum:        pool = momentum
        }
        let dayOrdinal = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        // Wrapping addition to avoid overflow
        let index = abs((dayOrdinal &+ seed) % pool.count)
        return pool[index]
    }
}
