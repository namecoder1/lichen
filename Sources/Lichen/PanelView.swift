import SwiftUI

/// Pannello della barra dei menu, in stile Centro di Controllo.
/// macOS 26+: Liquid Glass (GlassEffectContainer, vetro interattivo); prima: materiali traslucidi.
struct PanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        // Le due pagine restano sempre costruite: cambiare pagina cambia solo opacità e posizione
        // (ricrearle costava >50 ms per i controlli AppKit: menu, interruttori, cursori).
        // Ogni pagina ha il SUO contenitore di vetro: un contenitore unico disegna il vetro di entrambe
        // e ignora l'opacità dei figli, così la pagina nascosta restava visibile.
        ZStack(alignment: .top) {
            page(.main) { MainPage(model: model) }
            page(.settings) { SettingsPage(model: model) }
        }
        .animation(.easeOut(duration: 0.18), value: model.page)
        .padding(16)
        .frame(width: 364, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private func page<Content: View>(_ p: PanelPage, @ViewBuilder _ content: () -> Content) -> some View {
        let shown = model.page == p
        return GlassGroup(spacing: 10) { content() }
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { model.setPageHeight(g.size.height, for: p) }
                    .onChange(of: g.size.height) { model.setPageHeight($0, for: p) }
            })
            // la pagina nascosta non conta nell'altezza: altrimenti con pagine di altezza diversa
            // SwiftUI centra il contenuto e quella visibile finisce tagliata in alto
            .frame(height: shown || model.prewarming ? nil : 0, alignment: .top)
            .opacity(shown || model.prewarming ? 1 : 0)
            .offset(x: shown ? 0 : (p == .main ? -16 : 16))
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
    }
}

private struct MainPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            HeroCard(model: model)
            if model.screens.count > 1 { DisplayPicker(model: model) }
            ThemeStrip(model: model)
            TileGrid(model: model)
            FooterBar(model: model)
        }
    }
}

// MARK: - Anteprima grande del tema attivo

private struct HeroCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let img = model.theme.thumbnail {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: 332, height: 180)
            .clipped()
            .id(model.theme.id)
            .transition(.opacity)

            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.theme.name)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text(model.theme.tagline)
                    .font(.callout)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
            .padding(16)
        }
        .frame(width: 332, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .overlay(alignment: .topLeading) { statusChip.padding(10) }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                CircleButton(symbol: "slider.horizontal.3", help: "Regola il tema") {
                    Haptics.tick(); withAnimation(.snappy) { model.page = .settings }
                }
                CircleButton(symbol: "dice.fill", help: "Nuovo paesaggio") { model.actions?.newLandscape() }
                CircleButton(symbol: model.paused ? "play.fill" : "pause.fill",
                             help: model.paused ? "Riprendi" : "Pausa") { model.actions?.setPaused(!model.paused) }
            }
            .padding(10)
        }
        .animation(.easeInOut(duration: 0.35), value: model.theme.id)
    }

    @ViewBuilder private var statusChip: some View {
        if !model.trusted {
            Button { model.actions?.openAccessibilitySettings() } label: {
                Label("Concedi l'accesso", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .glassCapsule(tint: .orange)
        } else {
            Label(chipText, systemImage: chipSymbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glassCapsule()
        }
    }

    private var chipText: String {
        if model.paused { return "In pausa" }
        if model.autoPaused { return "Pausa automatica" }
        return "\(model.iconCount) icone"
    }

    private var chipSymbol: String {
        model.paused || model.autoPaused ? "pause.circle" : "square.grid.2x2"
    }
}

// MARK: - Schermo (con più monitor)

private struct DisplayPicker: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            pill(nil, "Tutti", "rectangle.on.rectangle")
            ForEach(model.screens) { s in pill(s.id, s.name, "display") }
        }
        .padding(4)
        .tileBackground(isOn: false, radius: 20)
    }

    private func pill(_ id: CGDirectDisplayID?, _ title: String, _ symbol: String) -> some View {
        let on = model.targetDisplay == id
        return Button {
            withAnimation(.snappy) { model.actions?.setTargetDisplay(id) }
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: on ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(Capsule().fill(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scelta del tema

private struct ThemeStrip: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ThemeCatalog.all) { theme in
                        ThemeChip(theme: theme, selected: theme.id == model.theme.id) {
                            withAnimation(.snappy) { model.actions?.selectTheme(theme) }
                        }
                        .id(theme.id)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(model.theme.id, anchor: .center) }
        }
    }
}

private struct ThemeChip: View {
    let theme: ThemeInfo
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let img = theme.thumbnail {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
                .frame(width: 84, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : .white.opacity(hover ? 0.45 : 0.12),
                                      lineWidth: selected ? 2.5 : 1)
                }
                .shadow(color: selected ? Color.accentColor.opacity(0.45) : .black.opacity(0.15),
                        radius: selected ? 8 : 3, y: 2)
                .scaleEffect(hover && !selected ? 1.04 : 1)

                Text(theme.name)
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: 84)
            }
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .help(theme.credit.map { "\(theme.tagline) — tema di \($0)" } ?? theme.tagline)
    }
}

// MARK: - Impostazioni del tema e atmosfera

private struct SettingsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { Haptics.tick(); withAnimation(.snappy) { model.page = .main } } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .glassCircleBackground()
                .help("Indietro")

                VStack(alignment: .leading, spacing: 0) {
                    Text(model.theme.name).font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(model.theme.credit.map { "Tema di \($0)" } ?? "Tema di Lichen")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.actions?.resetThemeSettings() } label: {
                    Text("Ripristina")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .glassCapsule(tint: nil, plain: true)
            }

            VStack(spacing: 14) {
                ForEach(model.theme.params) { p in ParamRow(model: model, param: p) }
            }
            .padding(16)
            .tileBackground(isOn: false, radius: 24)

            VStack(spacing: 0) {
                PickerRow(symbol: "sun.horizon", title: "Luce", selection: Binding(
                    get: { model.lightMode }, set: { model.actions?.setLightMode($0) }),
                          options: LightMode.allCases, label: \.label)
                Divider().padding(.leading, 44)
                PickerRow(symbol: "arrow.triangle.2.circlepath", title: "Cambia tema", selection: Binding(
                    get: { model.rotation }, set: { model.actions?.setRotation($0) }),
                          options: RotationMode.allCases, label: \.label)
                Divider().padding(.leading, 44)
                HStack(spacing: 10) {
                    RowIcon(symbol: "drop.circle")
                    Text("Increspature al clic").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.ripples }, set: { model.actions?.setRipples($0) }))
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .tileBackground(isOn: false, radius: 24)
        }
    }
}

private struct RowIcon: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 28, height: 28)
            .background(Circle().fill(.quaternary))
    }
}

private struct ParamRow: View {
    @ObservedObject var model: AppModel
    let param: ThemeParam

    private var value: Binding<Double> {
        Binding(get: { model.themeSettings[param.key] ?? param.def },
                set: { model.actions?.setThemeSetting(param.key, value: $0) })
    }

    var body: some View {
        switch param.kind {
        case .toggle:
            HStack(spacing: 10) {
                RowIcon(symbol: param.symbol)
                Text(param.label).font(.system(size: 12, weight: .medium))
                Spacer()
                Toggle("", isOn: Binding(get: { value.wrappedValue > 0.5 }, set: { value.wrappedValue = $0 ? 1 : 0 }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
        case let .slider(lo, hi, step):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    RowIcon(symbol: param.symbol)
                    Text(param.label).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(format(value.wrappedValue, lo: lo, hi: hi, step: step))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                // Niente `step:`: SwiftUI creerebbe un NSSlider con una tacca per ogni passo (fino a 160),
                // che AppKit ricalcola e ridisegna a ogni fotogramma. Il valore si arrotonda qui.
                Slider(value: Binding(get: { value.wrappedValue },
                                      set: { v in value.wrappedValue = step > 0 ? (v / step).rounded() * step : v }),
                       in: lo...hi)
                .controlSize(.small)
                .padding(.leading, 38)
            }
        }
    }

    /// Interi così come sono; i valori continui in percentuale.
    private func format(_ v: Double, lo: Double, hi: Double, step: Double) -> String {
        step >= 1 ? "\(Int(v.rounded()))" : "\(Int(((v - lo) / (hi - lo) * 100).rounded()))%"
    }
}

private struct PickerRow<T: Hashable & Identifiable>: View {
    let symbol: String, title: String
    @Binding var selection: T
    let options: [T]
    let label: KeyPath<T, String>

    var body: some View {
        HStack(spacing: 10) {
            RowIcon(symbol: symbol)
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            Menu {
                Picker(title, selection: $selection) {
                    ForEach(options) { Text($0[keyPath: label]).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Text(selection[keyPath: label]).font(.system(size: 12))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Riquadri in stile Centro di Controllo

private struct TileGrid: View {
    @ObservedObject var model: AppModel
    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: cols, spacing: 10) {
            Menu {
                Picker("Schermata di blocco", selection: Binding(
                    get: { model.lockMode }, set: { model.actions?.setLockMode($0) })) {
                    ForEach(LockMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                TileLabel(symbol: "lock.display", title: "Blocco",
                          subtitle: model.lockMode.short,
                          isOn: model.lockScreen)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .tileBackground(isOn: model.lockScreen)
            Tile(symbol: "sparkles.tv", title: "Salvaschermo",
                 subtitle: model.saverInstalled ? "Scegli in Impostazioni" : "Installa", isOn: model.saverInstalled) {
                model.actions?.installScreenSaver()
            }
            Menu {
                Picker("Qualità", selection: Binding(get: { model.qualityMode },
                                                     set: { model.actions?.setQualityMode($0) })) {
                    ForEach(QualityMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                TileLabel(symbol: "gauge.with.dots.needle.67percent", title: "Qualità",
                          subtitle: model.qualityReason, isOn: false)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .tileBackground(isOn: false)

            Tile(symbol: "power", title: "All'avvio",
                 subtitle: model.launchAtLogin ? "Si apre da sola" : "Disattivato", isOn: model.launchAtLogin) {
                model.toggleLaunchAtLogin(!model.launchAtLogin)
            }
        }
    }
}

private struct Tile: View {
    let symbol: String, title: String, subtitle: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TileLabel(symbol: symbol, title: title, subtitle: subtitle, isOn: isOn)
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .tileBackground(isOn: isOn)
    }
}

private struct TileLabel: View {
    let symbol: String, title: String, subtitle: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Piè di pagina

private struct FooterBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Toggle("Mostra nel Dock", isOn: Binding(get: { model.showInDock }, set: { model.actions?.setShowInDock($0) }))
                Button("Ricarica il tema") { model.actions?.reloadTheme() }
                if model.saverInstalled {
                    Button("Avvia il salvaschermo") { model.actions?.startScreenSaver() }
                }
                if model.canCheckForUpdates {
                    Button("Controlla aggiornamenti…") { model.actions?.checkForUpdates() }
                }
                Divider()
                Link("Temi Spiaggia e Prato: Deskland (GPL-3.0)", destination: URL(string: "https://github.com/BLEZZ0102/Deskland")!)
                Divider()
                Button("Esci da Lichen") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .contentShape(Circle())
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .glassCircleBackground()

            if let busy = model.busy {
                ProgressView().controlSize(.mini)
                Text(busy).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text("Lichen \(AppModel.version)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Bottoni tondi in vetro

private struct CircleButton: View {
    let symbol: String, help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .glassCircleBackground(dark: true)
        .help(help)
    }
}

// MARK: - Liquid Glass con ripiego per macOS < 26

struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder func tileBackground(isOn: Bool, radius: CGFloat = 28) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(isOn ? Glass.regular.tint(Color.accentColor.opacity(0.18)) : Glass.regular,
                             in: shape)
        } else {
            self.background(isOn ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.regularMaterial), in: shape)
        }
    }

    /// `plain`: capsula di vetro neutra (bottoni sul pannello, non sopra un'immagine).
    @ViewBuilder func glassCapsule(tint: Color? = nil, plain: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if plain {
                self.glassEffect(Glass.regular, in: .capsule)
            } else {
                self.glassEffect(tint.map { Glass.regular.tint($0.opacity(0.5)) } ?? Glass.regular.tint(.black.opacity(0.15)),
                                 in: .capsule)
            }
        } else if plain {
            self.background(.regularMaterial, in: Capsule())
        } else {
            self.background((tint ?? .black).opacity(0.35), in: Capsule())
        }
    }

    @ViewBuilder func glassCircleBackground(dark: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(dark ? Glass.regular.tint(.black.opacity(0.2)) : Glass.regular,
                             in: .circle)
        } else {
            self.background(dark ? AnyShapeStyle(Color.black.opacity(0.35)) : AnyShapeStyle(.regularMaterial), in: Circle())
        }
    }
}

/// Tutta la forma è cliccabile; leggero rimpicciolimento alla pressione (al posto del vetro "interattivo").
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.9
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
