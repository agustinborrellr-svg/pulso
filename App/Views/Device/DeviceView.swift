import SwiftUI
import PulsoStore

/// "CONFIGURACIÓN DEL DISPOSITIVO": connection, battery, heart-rate broadcast and the strap's tools.
struct DeviceView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var confirmForget = false
    @State private var diagnosticsURL: URL?
    @State private var pairing = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Configuración del dispositivo", back: { dismiss() }) {
                NavigationLink { PairingGuideView() } label: {
                    Image(systemName: "info.circle").font(.title3).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Guía de emparejamiento")
            }
            connectionHeader
                .padding(.horizontal, 20)
                .padding(.top, 8)
            HStack(spacing: 28) {
                tabButton("Estado", 0)
                tabButton("Avanzado", 1)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if tab == 0 { status } else { advanced }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
        }
        .background(PulsoBackground())
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $pairing) { PairingFlowView() }
    }

    private var connected: Bool { model.strapState.isConnected }
    private var modelName: String {
        if model.identity.hardware.isEmpty && model.identity.model.isEmpty { return "Pulse Band" }
        return model.identity.isMG ? "Pulse Band MG" : "Pulse Band 5.0"
    }

    private var connectionHeader: some View {
        let status = ConnectionStatus(model)
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.identity.name.isEmpty ? (model.identity.serial.isEmpty ? modelName : "Pulse Band \(model.identity.serial)") : Fmt.bandName(model.identity.name))
                    .scaledFont(19, weight: .bold, relativeTo: .title3, maxScale: 1.4)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                ConnectionBadge(status: status)
            }
            Spacer()
            Button {
                model.syncNow()
            } label: {
                VStack(alignment: .trailing, spacing: 3) {
                    Caps("Última sincronización", size: 11, color: Theme.secondary, weight: .semibold)
                    if syncing {
                        PulseLoaderLabel(text: "Sincronizando…", tint: Theme.strain)
                    } else {
                        Text(model.lastSync.map { Fmt.relative($0) } ?? "nunca").font(.subheadline.bold()).foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!connected || syncing)
            .accessibilityLabel("Última sincronización: \(model.lastSync.map { Fmt.relative($0) } ?? "nunca")")
            .accessibilityHint(connected ? "Toca para sincronizar ahora" : "")
        }
    }

    private var syncing: Bool {
        if case .syncing = model.strapState { return true }
        return false
    }

    private func tabButton(_ title: String, _ i: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { tab = i }
        } label: {
            VStack(spacing: 8) {
                Caps(title, size: 12, color: tab == i ? .white : Theme.secondary, weight: .semibold)
                Rectangle().fill(tab == i ? Color.white : Color.clear).frame(height: 2)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == i ? [.isSelected] : [])
    }

    // MARK: Estado

    private var status: some View {
        VStack(spacing: 16) {
            hero
            stateMessage
            sensorCard
            deviceCard
            Toggle(isOn: Binding(get: { model.settings.hrBroadcast }, set: { v in
                var s = model.settings
                s.hrBroadcast = v
                model.saveSettings(s)
            })) {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.link, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Caps("Transmitir FC", size: 13)
                        Text("A aplicaciones y dispositivos compatibles").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .tint(Theme.green)
            .padding(14)
            .cardSurface(radius: Metrics.rowRadius)
            if !model.strap.hasSavedStrap {
                Button("Vincular una pulsera") { pairing = true }
                    .buttonStyle(PrimaryCapsuleStyle())
            } else if connected {
                Button("Sincronizar ahora") { model.syncNow() }
                    .buttonStyle(SecondaryCapsuleStyle())
                    .disabled(syncing)
            }
        }
    }

    /// The band with its model and a vertical battery gauge.
    private var hero: some View {
        HStack(alignment: .center, spacing: 8) {
            StrapIllustration(metallic: model.identity.isMG)
                .frame(maxWidth: .infinity)
                .frame(height: 250)
            VStack(alignment: .trailing, spacing: 10) {
                if let b = model.battery {
                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 1) {
                                Text("\(Int(b))").scaledFont(44, weight: .bold, relativeTo: .largeTitle, maxScale: 1.2).monospacedDigit()
                                Text("%").scaledFont(18, weight: .bold, relativeTo: .title3, maxScale: 1.2)
                            }
                            .foregroundStyle(.white)
                            if model.charging == true {
                                Label("Cargando", systemImage: "bolt.fill").font(.caption.bold()).foregroundStyle(Theme.green)
                            }
                            Caps(modelName, size: 11, color: Theme.secondary, weight: .semibold)
                        }
                        ZStack(alignment: .bottom) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(b < 20 ? Theme.red : Theme.green).frame(height: 150 * b / 100)
                        }
                        .frame(width: 5, height: 150)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Batería")
                    .accessibilityValue("\(Int(b)) %\(model.charging == true ? ", cargando" : "")")
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("–").scaledFont(44, weight: .bold, relativeTo: .largeTitle, maxScale: 1.2).foregroundStyle(Theme.tertiary)
                        Caps("Batería sin leer", size: 11, color: Theme.secondary, weight: .semibold)
                        Caps(modelName, size: 11, color: Theme.secondary, weight: .semibold)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(minWidth: 120, alignment: .trailing)
        }
    }

    /// What the app actually knows about the link, the data and the skin contact.
    private var sensorCard: some View {
        let status = ConnectionStatus(model)
        return PCard(spacing: 0) {
            CardHeader(title: "Estado")
                .padding(.bottom, 10)
            infoRow("dot.radiowaves.left.and.right", "Bluetooth", linkText, connected ? Theme.green : Theme.secondary)
            divider
            infoRow("arrow.down.circle", "Datos", dataText(status), status.kind == .pending ? Theme.yellow : .white)
            divider
            infoRow("waveform.path.ecg", "Pulso en directo", liveText(status), status.liveFresh ? Theme.green : .white)
            divider
            infoRow("sensor", "Sensor", sensorText(status), .white)
        }
    }

    private var deviceCard: some View {
        PCard(spacing: 0) {
            CardHeader(title: "Dispositivo")
                .padding(.bottom, 10)
            infoRow("applewatch.side.right", "Modelo", modelName == "Pulse Band" ? "Sin confirmar" : modelName, .white)
            divider
            infoRow("cpu", "Firmware", model.identity.firmware.isEmpty ? "–" : model.identity.firmware, .white)
            divider
            infoRow("memorychip", "Hardware", model.identity.hardware.isEmpty ? "–" : model.identity.hardware, .white)
            divider
            infoRow("number", "Número de serie", model.identity.serial.isEmpty ? "–" : model.identity.serial, .white)
            divider
            infoRow("internaldrive", "Datos guardados", MoreView.storedText(model.rawSampleCount), .white)
        }
    }

    private var divider: some View { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 34) }

    private func infoRow(_ icon: String, _ key: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(Theme.secondary).frame(width: 24)
                .accessibilityHidden(true)
            Text(key).font(.subheadline).foregroundStyle(Theme.secondary)
            Spacer(minLength: 8)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(color)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var linkText: String {
        switch model.strapState {
        case .ready, .syncing: return "Conectada"
        case .scanning, .connecting: return "Conectando…"
        case .pairing: return "Emparejando…"
        case .pairingRefused: return "Emparejamiento rechazado"
        case .bluetoothOff: return "Bluetooth apagado"
        case .unauthorized: return "Sin permiso"
        case .unsupported: return "No compatible"
        case .noStrap: return model.strap.hasSavedStrap ? "Desconectada" : "Sin pulsera"
        }
    }

    private func dataText(_ status: ConnectionStatus) -> String {
        if syncing { return "Descargando…" }
        guard let last = model.lastSync else { return "Sin descargas" }
        return status.kind == .pending ? "Pendiente · \(Fmt.relative(last))" : "Al día · \(Fmt.relative(last))"
    }

    private func liveText(_ status: ConnectionStatus) -> String {
        if status.liveFresh, let hr = model.liveHR { return "\(hr) lpm" }
        guard let at = model.lastLiveAt else { return "Sin señal" }
        return "Sin señal · \(Fmt.relative(at))"
    }

    /// Only live beats prove skin contact; without them Pulso can't tell.
    private func sensorText(_ status: ConnectionStatus) -> String {
        if status.liveFresh { return "Leyendo tu pulso" }
        return connected ? "Sin lectura ahora" : "Desconocido"
    }

    @ViewBuilder
    private var stateMessage: some View {
        switch model.strapState {
        case .scanning:
            progressNotice("Buscando tu pulsera…", "Mantén la pulsera cerca del iPhone.", progress: nil)
        case .connecting:
            progressNotice("Conectando…", "Abriendo la conexión Bluetooth con la pulsera.", progress: 0.3)
        case .pairing:
            progressNotice("Emparejando…", "Acepta la solicitud de emparejamiento de iOS si aparece.", progress: 0.65)
        case .syncing(let n):
            progressNotice("Sincronizando…", n > 0 ? "Descargando datos de la pulsera · \(n) s" : "Descargando datos de la pulsera.", progress: nil)
        case .ready:
            if ConnectionStatus(model).kind == .pending {
                notice("Conectada, pero los datos tienen más de 2 horas. Pulso los descargará en la próxima sincronización automática, o toca «Sincronizar ahora».",
                       color: Theme.yellow, icon: "clock.badge.exclamationmark")
            } else if model.analyzing {
                progressNotice("Analizando…", "Calculando tus métricas con los datos nuevos.", progress: model.analysisProgress)
            } else {
                notice("Conectada y al día. Pulso descarga sola cada 30 minutos.", color: Theme.green, icon: "checkmark.circle")
            }
        case .noStrap:
            if model.strap.hasSavedStrap {
                notice("Sin conexión: la pulsera está fuera de alcance, sin batería o en uso por otra app. Pulso se reconecta en cuanto la encuentre.",
                       color: Theme.secondary, icon: "bolt.horizontal.circle")
            } else {
                notice("Todavía no hay ninguna pulsera vinculada.", color: Theme.secondary, icon: "plus.circle")
            }
        case .pairingRefused:
            notice(ConnectionStatus(model).liveFresh
                   ? "La pulsera no acepta el emparejamiento, pero envía el pulso en directo. Para descargar el histórico hay que liberarla de la app de su fabricante y del iPhone."
                   : "La pulsera no acepta el emparejamiento: suele seguir vinculada a la app de su fabricante o a un emparejamiento antiguo del iPhone.",
                   color: Theme.yellow)
        case .bluetoothOff:
            notice("El Bluetooth del iPhone está apagado.", color: Theme.yellow)
        case .unauthorized:
            notice("Pulso no tiene permiso de Bluetooth: actívalo en Ajustes → Pulso.", color: Theme.yellow)
        case .unsupported(let msg):
            notice(msg, color: Theme.yellow)
        }
    }

    private func progressNotice(_ title: String, _ text: String, progress: Double?) -> some View {
        HStack(spacing: 14) {
            PulseLoader(phase: .running(progress: progress), style: .compact)
                .frame(width: 54, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                Text(text).font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Metrics.rowRadius)
        .accessibilityElement(children: .combine)
    }

    private func notice(_ text: String, color: Color, icon: String = "info.circle") -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).accessibilityHidden(true)
            Text(text).font(.subheadline).foregroundStyle(color == Theme.secondary ? Color(white: 0.85) : color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous))
    }

    // MARK: Avanzado

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { pairing = true } label: {
                ActionRow(icon: "applewatch.radiowaves.left.and.right", title: model.strap.hasSavedStrap ? "Vincula otra pulsera" : "Vincula una pulsera",
                          detail: "Empareja una Pulse Band con Pulso. Nunca se conecta sola: tú eliges cuál.")
            }
            .buttonStyle(.plain)
            Button { model.syncNow() } label: {
                ActionRow(icon: "arrow.triangle.2.circlepath", title: "Sincronizar ahora",
                          detail: "Descarga ya lo que la pulsera tenga guardado.")
            }
            .buttonStyle(.plain)
            .disabled(!connected)
            NavigationLink { ConnectionLogView() } label: {
                ActionRow(icon: "list.bullet.rectangle", title: "Registro de conexión", detail: "Cada paso de la conexión, para entender qué pasa.")
            }
            .buttonStyle(.plain)
            Button {
                model.diagnosticsReport { diagnosticsURL = $0 }
            } label: {
                ActionRow(icon: "stethoscope", title: "Preparar diagnóstico", detail: "Un informe para analizar problemas de conexión.")
            }
            .buttonStyle(.plain)
            if let url = diagnosticsURL {
                ShareLink(item: url) {
                    ActionRow(icon: "square.and.arrow.up", title: "Enviar diagnóstico")
                }
                .buttonStyle(.plain)
            }
            NavigationLink { PairingGuideView() } label: {
                ActionRow(icon: "questionmark.circle", title: "Guía de emparejamiento", detail: "Qué hacer si la pulsera no se empareja.")
            }
            .buttonStyle(.plain)
            if model.strap.hasSavedStrap {
                Button { confirmForget = true } label: {
                    ActionRow(icon: "applewatch.slash", title: "Olvida la pulsera", detail: "Pulso deja de conectarse a ella. Tus datos se quedan en el iPhone.",
                              destructive: true)
                }
                .buttonStyle(.plain)
                .confirmationDialog("¿Olvidar esta pulsera?", isPresented: $confirmForget, titleVisibility: .visible) {
                    Button("Olvidar", role: .destructive) { model.forgetStrap() }
                }
            }
        }
    }
}

// MARK: - Pairing flow

/// Step by step pairing, one instruction per screen.
struct PairingFlowView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var pending: DiscoveredStrap?
    @State private var help = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if step == 0 { model.stopScan(); dismiss() } else { withAnimation { step -= 1 } }
                } label: {
                    Image(systemName: step == 0 ? "xmark" : "chevron.left").scaledFont(20, weight: .semibold, relativeTo: .body).frame(width: 44, height: 44)
                }
                .accessibilityLabel(step == 0 ? "Cerrar" : "Atrás")
                Spacer()
                if step == 2 { Caps("Modo de emparejamiento", size: 13) }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)

            Group {
                switch step {
                case 0: prepare
                case 1: tap
                case 2: choose
                default: finishing
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        }
        .background(PulsoBackground())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $help) { NavigationStack { PairingGuideView() }.preferredColorScheme(.dark) }
        .confirmationDialog(pending.map { "¿Emparejar con \($0.name)?" } ?? "",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Sí, es mi pulsera de pruebas") {
                if let s = pending { model.chooseStrap(s) }
                pending = nil
                withAnimation { step = 3 }
            }
            Button("Cancelar", role: .cancel) { pending = nil }
        } message: {
            Text("La pulsera solo admite un emparejamiento. Asegúrate de que no está vinculada a otra app.")
        }
    }

    private func stepLayout<Art: View>(title: String, text: String, primary: String, action: @escaping () -> Void,
                                       @ViewBuilder art: () -> Art) -> some View {
        VStack(spacing: 18) {
            art().frame(maxHeight: .infinity)
            Text(title).scaledFont(22, weight: .semibold, relativeTo: .title2, maxScale: 1.5).foregroundStyle(.white).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(text).font(.callout).foregroundStyle(Color(white: 0.8)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            Spacer(minLength: 20)
            VStack(spacing: 12) {
                Button(primary, action: action).buttonStyle(PrimaryCapsuleStyle())
                Button("¿Necesitas ayuda?") { help = true }.buttonStyle(SecondaryCapsuleStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private var prepare: some View {
        stepLayout(title: "Libera tu pulsera",
                   text: "La pulsera solo admite un emparejamiento. Desvincúlala de cualquier otra app y, en el iPhone, ve a Ajustes → Bluetooth y toca «Omitir este dispositivo».",
                   primary: "Hecho") { withAnimation { step = 1 } } art: {
            StrapIllustration(showSensors: true)
        }
    }

    private var tap: some View {
        stepLayout(title: "Toca rápidamente",
                   text: "Toca rápidamente la parte superior hasta que el indicador LED lateral parpadee en azul: eso es el modo de emparejamiento.",
                   primary: "Mi pulsera está azul") {
            withAnimation { step = 2 }
            model.scanForStraps()
        } art: {
            StrapIllustration(ledBlue: true, showSensors: false, tapHint: true)
        }
    }

    private var choose: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Selecciona tu pulsera").scaledFont(28, weight: .bold, relativeTo: .title1, maxScale: 1.4).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text("Si aparecen varias, mira el número de serie en el lateral de la tuya. Nada se conecta hasta que la elijas.")
                .font(.callout).foregroundStyle(Color(white: 0.8))
            if model.strapState == .scanning {
                HStack(spacing: 12) {
                    PulseLoader(phase: .running(progress: nil), style: .compact)
                        .frame(width: 40, height: 20)
                    Text(model.discoveredStraps.isEmpty ? "Buscando pulseras en modo emparejamiento…" : "Buscando más pulseras…")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                }
                .padding(.vertical, model.discoveredStraps.isEmpty ? 30 : 6)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 10) {
                    if model.discoveredStraps.isEmpty {
                        Text("No he encontrado ninguna pulsera. Comprueba que el LED parpadea en azul y que está cerca del iPhone.")
                            .font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    }
                    Button("Buscar de nuevo") { model.scanForStraps() }
                        .buttonStyle(SecondaryCapsuleStyle())
                }
                .padding(.vertical, 12)
            }
            ForEach(model.discoveredStraps) { s in
                Button { pending = s } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "applewatch.radiowaves.left.and.right").font(.title2).foregroundStyle(Theme.link)
                        VStack(alignment: .leading, spacing: 3) {
                            Caps(Fmt.bandName(s.name), size: 14)
                            Text(MoreView.signal(s.rssi)).font(.caption).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.secondary)
                    }
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle").foregroundStyle(Theme.link)
                Text("Una luz azul parpadeante en tu pulsera significa que está lista para emparejarse.")
                    .font(.subheadline).foregroundStyle(Theme.link)
            }
            .padding(14)
            .background(Theme.link.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            Button("Volver a buscar") { model.scanForStraps() }
                .buttonStyle(SecondaryCapsuleStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    /// Connecting → pairing → ready, with the pulse trace filling as each stage completes.
    @ViewBuilder
    private var finishing: some View {
        let ready = model.strapState.isConnected
        let refused = model.strapState == .pairingRefused
        stepLayout(title: ready ? "¡Conectada!" : (refused ? "No se ha podido emparejar" : finishingTitle),
                   text: ready ? "Tu pulsera ya está con Pulso. La primera descarga empieza sola."
                       : (refused ? "Suele ser porque sigue vinculada a otra app o a un emparejamiento antiguo. Revisa el primer paso y vuelve a intentarlo."
                           : "Acepta la solicitud de emparejamiento de iOS si aparece. Puede tardar unos segundos."),
                   primary: ready ? "Empezar" : (refused ? "Volver a intentar" : "Ver el registro")) {
            if ready { dismiss() } else if refused { withAnimation { step = 0 } } else { help = true }
        } art: {
            VStack(spacing: 28) {
                StrapIllustration(ledBlue: !ready && !refused, metallic: model.identity.isMG)
                    .frame(height: 220)
                PulseLoader(phase: ready ? .done : (refused ? .failed : .running(progress: finishingProgress)))
                    .frame(width: 200, height: 60)
                    .accessibilityLabel(ready ? "Conectada" : (refused ? "Emparejamiento fallido" : finishingTitle))
            }
        }
    }

    private var finishingTitle: String {
        switch model.strapState {
        case .pairing: return "Emparejando…"
        case .scanning, .connecting: return "Conectando…"
        default: return "Preparando…"
        }
    }

    private var finishingProgress: Double {
        switch model.strapState {
        case .scanning: return 0.12
        case .connecting: return 0.35
        case .pairing: return 0.7
        default: return 0.9
        }
    }
}
