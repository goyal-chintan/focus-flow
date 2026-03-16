import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allSettings: [AppSettings]

    private var settings: AppSettings {
        allSettings.first ?? AppSettings()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: FFSpacing.lg) {
                PremiumSurface(style: .hero) {
                    PremiumSectionHeader(
                        "Settings",
                        eyebrow: "Preferences",
                        subtitle: "Tune focus lengths, behavior, alerts, and startup behavior."
                    )
                }

                PremiumSurface(style: .card) {
                    PremiumSectionHeader("Durations", eyebrow: "Timers", subtitle: "Choose the pacing of focus and recovery.")
                    VStack(spacing: FFSpacing.sm) {
                        DurationRow(
                            label: "Focus",
                            icon: "timer",
                            color: FFColor.focus,
                            minutes: Binding(
                                get: { Int(settings.focusDuration / 60) },
                                set: { settings.focusDuration = TimeInterval($0 * 60); save() }
                            ),
                            range: 5...120,
                            step: 5
                        )
                        Divider()
                        DurationRow(
                            label: "Short Break",
                            icon: "cup.and.saucer.fill",
                            color: FFColor.success,
                            minutes: Binding(
                                get: { Int(settings.shortBreakDuration / 60) },
                                set: { settings.shortBreakDuration = TimeInterval($0 * 60); save() }
                            ),
                            range: 1...30,
                            step: 1
                        )
                        Divider()
                        DurationRow(
                            label: "Long Break",
                            icon: "figure.walk",
                            color: FFColor.deepFocus,
                            minutes: Binding(
                                get: { Int(settings.longBreakDuration / 60) },
                                set: { settings.longBreakDuration = TimeInterval($0 * 60); save() }
                            ),
                            range: 5...60,
                            step: 5
                        )
                        Divider()
                        HStack {
                            Label("Sessions before long break", systemImage: "repeat.circle.fill")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Stepper(
                                "\(settings.sessionsBeforeLongBreak)",
                                value: Binding(
                                    get: { settings.sessionsBeforeLongBreak },
                                    set: { settings.sessionsBeforeLongBreak = $0; save() }
                                ),
                                in: 2...8
                            )
                            .frame(width: 100)
                        }
                        .font(FFType.body)
                    }
                }

                PremiumSurface(style: .card) {
                    PremiumSectionHeader("Behavior", eyebrow: "Automation", subtitle: "Control how sessions and the app behave by default.")
                    VStack(spacing: FFSpacing.sm) {
                        ToggleRow(
                            label: "Auto-start breaks",
                            icon: "play.circle.fill",
                            color: FFColor.success,
                            isOn: Binding(
                                get: { settings.autoStartBreak },
                                set: { settings.autoStartBreak = $0; save() }
                            )
                        )
                        Divider()
                        ToggleRow(
                            label: "Auto-start next session",
                            icon: "arrow.clockwise.circle.fill",
                            color: FFColor.focus,
                            isOn: Binding(
                                get: { settings.autoStartNextSession },
                                set: { settings.autoStartNextSession = $0; save() }
                            )
                        )
                        Divider()
                        ToggleRow(
                            label: "Launch at login",
                            icon: "power.circle.fill",
                            color: FFColor.warning,
                            isOn: Binding(
                                get: { settings.launchAtLogin },
                                set: {
                                    settings.launchAtLogin = $0
                                    save()
                                    setLaunchAtLogin($0)
                                }
                            )
                        )
                    }
                }

                PremiumSurface(style: .card) {
                    PremiumSectionHeader("Sound", eyebrow: "Feedback", subtitle: "Choose the sound that marks the end of a session.")
                    HStack {
                        Label("Completion sound", systemImage: "speaker.wave.2.fill")
                            .font(FFType.body)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.completionSound },
                            set: {
                                settings.completionSound = $0
                                save()
                                NSSound(named: NSSound.Name($0))?.play()
                            }
                        )) {
                            ForEach(systemSounds, id: \.self) { sound in
                                Text(sound).tag(sound)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                    }
                }

                PremiumSurface(style: .card, alignment: .center) {
                    PremiumSectionHeader("About", eyebrow: "FocusFlow")
                    VStack(spacing: FFSpacing.sm) {
                        ZStack {
                            RoundedRectangle(cornerRadius: FFRadius.hero, style: .continuous)
                                .fill(FFColor.focus.opacity(0.15))
                                .frame(width: 72, height: 72)

                            Image(systemName: "bolt.circle.fill")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(FFColor.focus)
                        }

                        VStack(spacing: 4) {
                            Text("FocusFlow")
                                .font(FFType.title)
                            Text("Pomodoro focus timer for macOS")
                                .font(FFType.meta)
                                .foregroundStyle(.secondary)
                            Text("v1.0")
                                .font(FFType.micro)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(FFSpacing.lg)
        }
    }

    private func save() {
        try? modelContext.save()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    private let systemSounds = [
        "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]
}

// MARK: - Sub-components

private struct DurationRow: View {
    let label: String
    let icon: String
    let color: Color
    @Binding var minutes: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(color)
                .font(FFType.body)
            Spacer()
            Stepper(
                "\(minutes) min",
                value: $minutes,
                in: range,
                step: step
            )
            .frame(width: 140)
            .font(FFType.body)
        }
    }
}

private struct ToggleRow: View {
    let label: String
    let icon: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(label, systemImage: icon)
                .foregroundStyle(color)
                .font(FFType.body)
        }
    }
}
