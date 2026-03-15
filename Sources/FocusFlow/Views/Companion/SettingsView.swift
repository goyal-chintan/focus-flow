import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allSettings: [AppSettings]

    private var settings: AppSettings {
        if let s = allSettings.first { return s }
        let s = AppSettings()
        modelContext.insert(s)
        return s
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // Durations
                GroupBox {
                    VStack(spacing: 14) {
                        DurationRow(
                            label: "Focus",
                            icon: "timer",
                            color: .blue,
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
                            color: .green,
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
                            color: .purple,
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
                        .font(.subheadline)
                    }
                    .padding(4)
                } label: {
                    Label("Durations", systemImage: "clock.fill")
                        .font(.subheadline.weight(.semibold))
                }

                // Behavior
                GroupBox {
                    VStack(spacing: 12) {
                        ToggleRow(
                            label: "Auto-start breaks",
                            icon: "play.circle.fill",
                            color: .green,
                            isOn: Binding(
                                get: { settings.autoStartBreak },
                                set: { settings.autoStartBreak = $0; save() }
                            )
                        )
                        Divider()
                        ToggleRow(
                            label: "Auto-start next session",
                            icon: "arrow.clockwise.circle.fill",
                            color: .blue,
                            isOn: Binding(
                                get: { settings.autoStartNextSession },
                                set: { settings.autoStartNextSession = $0; save() }
                            )
                        )
                        Divider()
                        ToggleRow(
                            label: "Launch at login",
                            icon: "power.circle.fill",
                            color: .orange,
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
                    .padding(4)
                } label: {
                    Label("Behavior", systemImage: "gearshape.fill")
                        .font(.subheadline.weight(.semibold))
                }

                // Sound
                GroupBox {
                    HStack {
                        Label("Completion sound", systemImage: "speaker.wave.2.fill")
                            .font(.subheadline)
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
                        .frame(width: 140)
                    }
                    .padding(4)
                } label: {
                    Label("Sound", systemImage: "music.note")
                        .font(.subheadline.weight(.semibold))
                }

                // App info
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FocusFlow")
                                .font(.subheadline.weight(.semibold))
                            Text("Pomodoro focus timer for macOS")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("v1.0")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(4)
                } label: {
                    Label("About", systemImage: "info.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(24)
        }
        .background(.background)
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
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
            Stepper(
                "\(minutes) min",
                value: $minutes,
                in: range,
                step: step
            )
            .frame(width: 140)
            .font(.subheadline)
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
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }
}
