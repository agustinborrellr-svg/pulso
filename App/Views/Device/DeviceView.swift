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
                    Image(systemName: "info.circle").font(.title3).frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
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

    private var connectionHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Caps(connected ? "Conectado a" : (model.strap.hasSavedStrap ? "Sin conexión" : "Sin pulsera"), size: 11,
                     color: connected ? Theme.green : Theme.worse, weight: .semibold)
                Text(model.identity.name.isEmpty ? (model.identity.serial.isEmpty ? "WHOOP 5.0" : "WHOOP \(model.identity.serial)") : model.identity.name)
                    .font(.system(size: 19, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                model.syncNow()
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Caps("Última sincronización", size: 10, color: Theme.secondary, weight: .semibold)
                        Text(model.lastSync.map { Fmt.clock($0) } ?? "nunca").font(.caption.bold()).foregroundStyle(.white)
                    }
                    Image(systemName: syncing ? "arrow.triangle.2.circlepath.icloud" : "checkmark.icloud")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, isActive: syncing)
                }
            }
            .buttonStyle(.plain)
            .disabled(!connected)
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
    }

    // MARK: Estado

    private var status: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .trailing) {
                StrapIllustration(ledBlue: false, showSensors: false)
                    .frame(height: 300)
                    .offset(x: -40)
                if let b = model.battery {
                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 1) {
                                Text("\(Int(b))").font(.system(size: 44, weight: .bold)).monospacedDigit()
                                Text("%").font(.system(size: 18, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            Caps(model.identity.isMG ? "WHOOP MG" : "WHOOP 5.0", size: 11, color: Theme.secondary, weight: .semibold)
                        }
                        ZStack(alignment: .bottom) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(b < 20 ? Theme.red : Theme.green).frame(height: 170 * b / 100)
                        }
                        .frame(width: 5, height: 170)
                    }
                }
            }
            stateMessage
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
                    VStack(alignment: .leading, spacing: 3) {
                        Caps("Transmitir FC", size: 13)
                        Caps("A aplicaciones y dispositivos compatibles", size: 9, color: Theme.secondary, weight: .semibold)
                    }
                }
            }
            .tint(Theme.green)
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if !model.strap.hasSavedStrap {
                Button("Vincular una pulsera") { pairing = true }
                    .buttonStyle(PrimaryCapsuleStyle())
            }
            HStack {
                Caps("Datos guardados", size: 11, color: Theme.secondary, weight: .semibold)
                Spacer()
                Text(MoreView.storedText(model.rawSampleCount)).font(.subheadline.bold()).foregroundStyle(.white)
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var stateMessage: some View {
        switch model.strapState {
        case .pairingRefused:
            notice("La pulsera no acepta el emparejamiento: suele seguir vinculada a la app de WHOOP o a un emparejamiento antiguo del iPhone.",
                   color: Theme.yellow)
        case .bluetoothOff:
            notice("El Bluetooth del iPhone está apagado.", color: Theme.yellow)
        case .unauthorized:
            notice("Pulso no tiene permiso de Bluetooth: actívalo en Ajustes → Pulso.", color: Theme.yellow)
        case .unsupported(let msg):
            notice(msg, color: Theme.yellow)
        case .syncing(let n):
            notice("Descargando datos de la pulsera… \(n) s", color: Theme.link)
        default:
            EmptyView()
        }
    }

    private func notice(_ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(color)
            Text(text).font(.subheadline).foregroundStyle(color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Avanzado

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                info("applewatch.side.right", "Identificador del dispositivo", model.identity.serial.isEmpty ? "–" : model.identity.serial)
                info("cpu", "Firmware", model.identity.firmware.isEmpty ? "–" : model.identity.firmware)
            }
            .padding(.vertical, 18)
            Button { pairing = true } label: {
                ActionRow(icon: "applewatch.radiowaves.left.and.right", title: model.strap.hasSavedStrap ? "Vincula otra pulsera" : "Vincula una pulsera",
                          detail: "Empareja una WHOOP con Pulso. Nunca se conecta sola: tú eliges cuál.")
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

    private func info(_ icon: String, _ k: String, _ v: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2.weight(.light)).foregroundStyle(Theme.secondary)
            Caps(k, size: 10, color: Theme.secondary, weight: .semibold).multilineTextAlignment(.center)
            Text(v).font(.caption.bold().monospacedDigit()).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
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
                    Image(systemName: step == 0 ? "xmark" : "chevron.left").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
                }
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
            Text("Una WHOOP solo admite un emparejamiento. Asegúrate de que no es la pulsera vinculada a tu cuenta de WHOOP.")
        }
    }

    private func stepLayout<Art: View>(title: String, text: String, primary: String, action: @escaping () -> Void,
                                       @ViewBuilder art: () -> Art) -> some View {
        VStack(spacing: 18) {
            art().frame(maxHeight: .infinity)
            Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            Text(text).font(.system(size: 16)).foregroundStyle(Color(white: 0.8)).multilineTextAlignment(.center)
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
                   text: "Una WHOOP solo admite un emparejamiento. Desvincúlala de la app de WHOOP y, en el iPhone, ve a Ajustes → Bluetooth y toca «Omitir este dispositivo».",
                   primary: "Hecho") { withAnimation { step = 1 } } art: {
            StrapIllustration(ledBlue: false, showSensors: true)
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
            Text("Selecciona tu pulsera").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
            Text("Si aparecen varias, mira el número de serie en el lateral de la tuya. Nada se conecta hasta que la elijas.")
                .font(.system(size: 16)).foregroundStyle(Color(white: 0.8))
            if model.discoveredStraps.isEmpty {
                HStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Buscando pulseras en modo emparejamiento…").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
            }
            ForEach(model.discoveredStraps) { s in
                Button { pending = s } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "applewatch.radiowaves.left.and.right").font(.title2).foregroundStyle(Theme.link)
                        VStack(alignment: .leading, spacing: 3) {
                            Caps(s.name, size: 14)
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

    @ViewBuilder
    private var finishing: some View {
        let ready = model.strapState == .ready
        let refused = model.strapState == .pairingRefused
        stepLayout(title: ready ? "¡Conectada!" : (refused ? "No se ha podido emparejar" : "Emparejando…"),
                   text: ready ? "Tu pulsera ya está con Pulso. La primera descarga empieza sola."
                       : (refused ? "Suele ser porque sigue vinculada a la app de WHOOP o a un emparejamiento antiguo. Revisa el primer paso y vuelve a intentarlo."
                           : "Acepta la solicitud de emparejamiento de iOS si aparece. Puede tardar unos segundos."),
                   primary: ready ? "Empezar" : (refused ? "Volver a intentar" : "Ver el registro")) {
            if ready { dismiss() } else if refused { withAnimation { step = 0 } } else { help = true }
        } art: {
            ZStack {
                StrapIllustration(ledBlue: !ready, showSensors: false)
                if ready {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.green)
                        .offset(x: 90, y: -90)
                        .transition(.scale)
                }
            }
        }
    }
}

// MARK: - Illustration

/// A stylised strap drawn in code: braided band, the sensor pod, an optional pulsing LED.
struct StrapIllustration: View {
    var ledBlue = false
    var showSensors = false
    var tapHint = false
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height * 1.1)
            ZStack {
                // Band.
                Ellipse()
                    .stroke(
                        LinearGradient(colors: [Color(white: 0.16), Color(white: 0.07)], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: w * 0.16)
                    )
                    .overlay(
                        Ellipse()
                            .stroke(style: StrokeStyle(lineWidth: w * 0.15, dash: [2, 3]))
                            .foregroundStyle(Color.white.opacity(0.05))
                    )
                    .frame(width: w * 0.78, height: w * 0.58)
                    .rotationEffect(.degrees(-18))
                // Pod.
                RoundedRectangle(cornerRadius: w * 0.06, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: w * 0.06, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .frame(width: w * 0.44, height: w * 0.2)
                    .overlay {
                        if showSensors {
                            HStack(spacing: w * 0.02) {
                                ForEach(0..<4, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.35)).frame(width: w * 0.045, height: w * 0.06)
                                }
                            }
                        } else {
                            Text("PULSO").font(.system(size: w * 0.035, weight: .heavy)).tracking(2).foregroundStyle(Color.white.opacity(0.25))
                        }
                    }
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(ledBlue ? Theme.link : Color(white: 0.3))
                            .frame(width: w * 0.05, height: w * 0.014)
                            .shadow(color: ledBlue ? Theme.link : .clear, radius: pulse ? 10 : 2)
                            .opacity(ledBlue ? (pulse ? 1 : 0.35) : 1)
                            .offset(x: w * 0.03, y: w * 0.07)
                    }
                    .rotationEffect(.degrees(-18))
                    .offset(y: -w * 0.2)
                if tapHint {
                    VStack(spacing: 0) {
                        Circle().fill(Theme.link).frame(width: 12, height: 12)
                            .scaleEffect(pulse ? 1.3 : 0.9)
                        Rectangle().fill(Theme.link.opacity(0.7))
                            .frame(width: 1.5, height: w * 0.35)
                            .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
                    }
                    .offset(y: -w * 0.05)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
