import AppKit
import ServiceManagement
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
    @Published var flakesOverWindows: Bool { didSet { defaults.set(flakesOverWindows, forKey: "flakesOverWindows") } }
    @Published var snowOnWindows: Bool { didSet { defaults.set(snowOnWindows, forKey: "snowOnWindows") } }
    @Published var snowOnDock: Bool { didSet { defaults.set(snowOnDock, forKey: "snowOnDock") } }
    @Published var snowOnFloor: Bool { didSet { defaults.set(snowOnFloor, forKey: "snowOnFloor") } }
    @Published var liftSnowWithDock: Bool { didSet { defaults.set(liftSnowWithDock, forKey: "liftSnowWithDock") } }
    @Published var shakeOffSnow: Bool { didSet { defaults.set(shakeOffSnow, forKey: "shakeOffSnow") } }
    @Published var bankDepth: Double { didSet { defaults.set(bankDepth, forKey: "bankDepth") } }
    @Published var buildup: Double { didSet { defaults.set(buildup, forKey: "buildup") } }
    @Published var smoothAnimation: Bool { didSet { defaults.set(smoothAnimation, forKey: "smoothAnimation") } }
    @Published var tool: SnowTool = .cursor

    var hasSnowSurfaces: Bool { snowOnWindows || snowOnDock || snowOnFloor }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snowfall = Snowfall(rawValue: defaults.string(forKey: "snowfall") ?? "") ?? .steady
        wind = min(1, max(-1, defaults.double(forKey: "wind")))
        paused = defaults.bool(forKey: "paused")
        fullscreenPause = defaults.object(forKey: "fullscreenPause") as? Bool ?? true
        flakesOverWindows = defaults.object(forKey: "flakesOverWindows") as? Bool ?? false
        snowOnWindows = defaults.object(forKey: "snowOnWindows") as? Bool ?? true
        snowOnDock = defaults.object(forKey: "snowOnDock") as? Bool ?? true
        snowOnFloor = defaults.object(forKey: "snowOnFloor") as? Bool ?? true
        liftSnowWithDock = defaults.object(forKey: "liftSnowWithDock") as? Bool ?? true
        shakeOffSnow = defaults.object(forKey: "shakeOffSnow") as? Bool ?? true
        bankDepth = min(30, max(6, defaults.object(forKey: "bankDepth") as? Double ?? 18))
        buildup = min(2, max(0.25, defaults.object(forKey: "buildup") as? Double ?? 1))
        smoothAnimation = defaults.bool(forKey: "smoothAnimation")
    }
}

struct SettingsView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case weather = "Снегопад"
        case banks = "Сугробы"
        case controls = "Управление"

        var id: Self { self }
    }

    @ObservedObject var settings: SnowSettings
    let clear: () -> Void
    @State private var section = Section.weather
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    private let accent = Color(red: 0.69, green: 0.83, blue: 1)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Picker("Раздел настроек", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)

            Group {
                switch section {
                case .weather: weather
                case .banks: banks
                case .controls: controls
                }
            }
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            .padding(16)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.10))
                    .allowsHitTesting(false)
            }
        }
        .padding(20)
        .frame(width: 460)
        .tint(accent)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .background {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.17, blue: 0.30), Color(red: 0.055, green: 0.075, blue: 0.14)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }

    private var weather: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                sectionTitle("Интенсивность", icon: "cloud.snow")
                Picker("Интенсивность", selection: $settings.snowfall) {
                    ForEach(Snowfall.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)
            }
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
            Toggle("Падающий снег поверх окон", isOn: $settings.flakesOverWindows)
                .toggleStyle(.checkbox)
            Text("Выключи, чтобы снежинки были видны только на свободных участках экрана.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Частота кадров", selection: $settings.smoothAnimation) {
                Text("30 кадр/с").tag(false)
                Text("60 кадр/с").tag(true)
            }
            .pickerStyle(.segmented)
            .help("30 кадр/с снижает нагрузку. В режиме энергосбережения частота уменьшается автоматически.")
        }
    }

    private var banks: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Где накапливается снег", icon: "square.stack")
            HStack(spacing: 16) {
                Toggle("Окна", isOn: $settings.snowOnWindows)
                Toggle("Dock", isOn: $settings.snowOnDock)
                Toggle("Низ экрана", isOn: $settings.snowOnFloor)
            }
            .toggleStyle(.checkbox)
            Toggle("Поднимать снег вместе с Dock", isOn: $settings.liftSnowWithDock)
                .toggleStyle(.checkbox)
                .disabled(!settings.snowOnDock || !settings.snowOnFloor)
                .help("При появлении Dock снег переходит на него, при скрытии возвращается вниз.")
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                slider("Высота сугроба", value: $settings.bankDepth, range: 6...30, step: 1,
                       formatted: "\(Int(settings.bankDepth)) пт")
                slider("Скорость накопления", value: $settings.buildup, range: 0.25...2, step: 0.25,
                       formatted: "\(Int(settings.buildup * 100))%")
            }
            .disabled(!settings.hasSnowSurfaces)
            Toggle("Стряхивать снег при резком движении окна", isOn: $settings.shakeOffSnow)
                .toggleStyle(.checkbox)
                .disabled(!settings.snowOnWindows)
            Button(action: clear) {
                Label("Очистить сугробы и снежки", systemImage: "sparkles")
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 7) {
                sectionTitle("Инструмент", icon: "hand.point.up.left")
                Picker("Инструмент", selection: $settings.tool) {
                    ForEach(SnowTool.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)
                Text(settings.tool.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 34, alignment: .topLeading)
            }
            Divider()
            Toggle("Пауза в полноэкранном режиме", isOn: $settings.fullscreenPause)
                .toggleStyle(.checkbox)
            Toggle("Запускать при входе в macOS", isOn: Binding(
                get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                set: setLaunchAtLogin
            ))
            .toggleStyle(.checkbox)
            if loginStatus == .requiresApproval {
                Button("Подтвердить в системных настройках") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
            if let loginError {
                Text(loginError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        loginError = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            if service.status != .requiresApproval {
                loginError = "Не удалось изменить автозапуск. Проверь объекты входа в настройках macOS."
            }
        }
        loginStatus = service.status
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                        step: Double, formatted: String) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(formatted).font(.caption.monospacedDigit()).foregroundStyle(accent)
            }
            Slider(value: value, in: range, step: step) { Text(title) }.labelsHidden()
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
