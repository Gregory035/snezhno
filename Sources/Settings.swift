import AppKit
import SwiftUI

enum Snowfall: String, CaseIterable, Identifiable {
    case light, steady, blizzard

    var id: Self { self }
    var label: String {
        switch self {
        case .light: "Лёгкий"
        case .steady: "Ровный"
        case .blizzard: "Метель"
        }
    }

    var density: CGFloat {
        switch self {
        case .light: 0.00022
        case .steady: 0.00048
        case .blizzard: 0.00088
        }
    }

    var speed: CGFloat {
        switch self {
        case .light: 0.83
        case .steady: 1
        case .blizzard: 1.36
        }
    }
}

enum SnowTool: String, CaseIterable, Identifiable {
    case cursor, mitten, snowball

    var id: Self { self }
    var label: String {
        switch self {
        case .cursor: "Курсор"
        case .mitten: "Варежка"
        case .snowball: "Снежки"
        }
    }

    var symbol: String {
        switch self {
        case .cursor: "cursorarrow"
        case .mitten: "hand.raised"
        case .snowball: "snowflake"
        }
    }

    var hint: String {
        switch self {
        case .cursor: "Клики проходят сквозь снег."
        case .mitten: "Проведи курсором вдоль сугроба, чтобы смахнуть снег."
        case .snowball: "Зажми и веди по сугробу, затем отпусти. Сложи три кома от большего к меньшему. Esc возвращает курсор."
        }
    }
}

final class SnowSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var snowfall: Snowfall { didSet { defaults.set(snowfall.rawValue, forKey: "snowfall") } }
    @Published var wind: Double { didSet { defaults.set(wind, forKey: "wind") } }
    @Published var paused: Bool { didSet { defaults.set(paused, forKey: "paused") } }
    @Published var fullscreenPause: Bool { didSet { defaults.set(fullscreenPause, forKey: "fullscreenPause") } }
    @Published var tool: SnowTool = .cursor

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snowfall = Snowfall(rawValue: defaults.string(forKey: "snowfall") ?? "") ?? .steady
        wind = min(1, max(-1, defaults.double(forKey: "wind")))
        paused = defaults.bool(forKey: "paused")
        fullscreenPause = defaults.object(forKey: "fullscreenPause") as? Bool ?? true
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SnowSettings
    let clear: () -> Void

    private let accent = Color(red: 0.69, green: 0.83, blue: 1)

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            header
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 7) {
                    sectionTitle("Снегопад", icon: "cloud.snow")
                    Picker("Снегопад", selection: $settings.snowfall) {
                        ForEach(Snowfall.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.large)
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        sectionTitle("Ветер", icon: "wind")
                        Spacer()
                        Button(windLabel) { settings.wind = 0 }
                            .buttonStyle(.plain)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(accent)
                            .help("Сбросить ветер")
                    }
                    HStack(spacing: 11) {
                        Image(systemName: "arrow.left").foregroundStyle(.secondary)
                        Slider(value: $settings.wind, in: -1...1, step: 0.05) { Text("Ветер") }
                            .labelsHidden()
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    sectionTitle("Инструмент", icon: "hand.point.up.left")
                    Picker("Инструмент", selection: $settings.tool) {
                        ForEach(SnowTool.allCases) { tool in
                            Text(tool.label).tag(tool)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.large)
                    Text(settings.tool.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(height: 33, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(15)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.10))
                    .allowsHitTesting(false)
            }

            HStack {
                Toggle("Пауза в полноэкранном режиме", isOn: $settings.fullscreenPause)
                    .toggleStyle(.checkbox)
                Spacer()
                Button(action: clear) {
                    Label("Очистить снег", systemImage: "sparkles")
                }
                .help("Убрать все сугробы и снежки")
            }
            .font(.system(size: 12))
        }
        .padding(20)
        .frame(width: 440)
        .tint(accent)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .background {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.17, blue: 0.30), Color(red: 0.055, green: 0.075, blue: 0.14)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "snowflake")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 46, height: 46)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Снежно").font(.system(size: 25, weight: .semibold))
                Text(settings.paused ? "Снегопад на паузе" : "Снег идёт")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                settings.paused.toggle()
            } label: {
                Label(settings.paused ? "Продолжить" : "Пауза",
                      systemImage: settings.paused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var windLabel: String {
        let amount = Int((abs(settings.wind) * 100).rounded())
        if amount == 0 { return "Штиль" }
        return "\(settings.wind < 0 ? "←" : "→") \(amount)%"
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 13, weight: .semibold))
    }
}
