import SwiftUI
import WhoopProtocol

/// Technical tools: raw frame capture (to reverse-engineer unknown streams such as the MG's ECG), haptic
/// waveform tester and connection details. Nothing here is needed to use Pulso normally.
struct LabView: View {
    @EnvironmentObject var model: AppModel
    @State private var capturing = false
    @State private var captureAll = false
    @State private var exportURL: URL?
    @State private var counts: [UInt8: Int] = [:]
    @State private var effectA = 47
    @State private var effectB = 152
    @State private var loops = 2

    var body: some View {
        Form {
            Group {
            Section {
                Toggle("Grabar tramas", isOn: $capturing)
                    .onChange(of: capturing) { _, on in model.strap.setCapture(on, all: captureAll) }
                Toggle("Grabar también las conocidas", isOn: $captureAll)
                    .onChange(of: captureAll) { _, all in if capturing { model.strap.setCapture(true, all: all) } }
                Button("Crear archivo para compartir") {
                    model.strap.exportCapture { text, c in
                        counts = c
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pulso-captura-\(Int(Date().timeIntervalSince1970)).txt")
                        if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil { exportURL = url }
                    }
                }
                if let url = exportURL {
                    ShareLink(item: url) { Label("Compartir captura", systemImage: "square.and.arrow.up") }
                }
                Button("Borrar captura", role: .destructive) {
                    model.strap.clearCapture()
                    counts = [:]
                    exportURL = nil
                }
                if !counts.isEmpty {
                    ForEach(counts.keys.sorted(), id: \.self) { t in
                        LabeledContent("Tipo \(t)\(Self.typeName(t))", value: "\(counts[t] ?? 0)")
                            .font(.caption.monospaced())
                    }
                }
            } header: {
                Text("Captura de tramas")
            } footer: {
                Text("«Grabar tramas» guarda en memoria (hasta 20.000) los mensajes de la pulsera que Pulso aún no entiende, por ejemplo el ECG de una MG. «También las conocidas» añade los que sí entiende (pulso, historial…), útil para comparar; gasta algo más de memoria pero no de batería de la pulsera. La grabación se para al salir de esta pantalla y no se guarda sola: «Crear archivo» hace un .txt temporal (hora, canal y bytes en hexadecimal) para enviarlo y descifrar el formato. Nunca contiene tu nombre ni tus métricas calculadas.")
            }

            Section {
                Stepper("Efecto A: \(effectA)", value: $effectA, in: 1...251)
                Stepper("Efecto B: \(effectB)", value: $effectB, in: 0...251)
                Stepper("Repeticiones: \(loops)", value: $loops, in: 1...8)
                Button("Vibrar") {
                    model.strap.haptic(effects: [UInt8(effectA), UInt8(effectB)], loops: UInt8(loops))
                }
                .disabled(!model.strapState.isConnected)
                Button("Parar vibración") { model.strap.stopHaptics() }
                Button("Respiración guiada con vibración (1 min)") { model.startBreathingGuide() }
                    .disabled(!model.strapState.isConnected || model.breathingGuideActive)
            } header: {
                Text("Vibración")
            } footer: {
                Text("Prueba formas de onda del motor de vibración (efectos 1–251; la pareja 47/152 es la de las notificaciones normales). Sirve para elegir vibraciones para alarmas y avisos. Solo hace vibrar: no cambia ningún ajuste de la pulsera.")
            }

            Section {
                Picker("Modo de conexión", selection: Binding(get: { model.strap.forcedMode?.rawValue ?? "auto" }, set: { v in
                    model.strap.setForcedMode(HandshakeMode(rawValue: v))
                })) {
                    Text("Automático").tag("auto")
                    ForEach(HandshakeMode.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                LabeledContent("En uso", value: model.strap.mode.label)
                LabeledContent("Último que funcionó", value: model.strap.workedMode?.label ?? "ninguno aún")
            } header: {
                Text("Emparejamiento")
            } footer: {
                Text("En automático, si un modo falla Pulso prueba el otro solo. Secuencial sigue el orden de OpenStrap: suscripciones de una en una, con esperas.")
            }

            Section {
                LabeledContent("Estado", value: "\(model.strapState)")
                LabeledContent("Modelo", value: model.identity.isMG ? "MG" : "5.0")
                LabeledContent("Hardware", value: model.identity.hardware.isEmpty ? "–" : model.identity.hardware)
                LabeledContent("Firmware", value: model.identity.firmware.isEmpty ? "–" : model.identity.firmware)
                LabeledContent("Registros sin decodificar guardados", value: "\((try? model.db.undecodedRecordCount()) ?? 0)")
                NavigationLink("Registro de conexión") { ConnectionLogView() }
            } header: {
                Text("Pulsera")
            } footer: {
                Text("Los registros del historial en un formato que esta versión no sabe leer se guardan tal cual antes de confirmarlos a la pulsera, para no perderlos: una versión futura podrá leerlos.")
            }
                    }
            .listRowBackground(Theme.card)
        }
        .pulsoList()
        .pulsoTitle("Laboratorio")
        .onDisappear {
            if capturing { model.strap.setCapture(false, all: false) }
        }
    }

    static func typeName(_ t: UInt8) -> String {
        guard let p = PacketType(rawValue: t) else { return " (desconocido)" }
        switch p {
        case .commandResponse, .puffinCommandResponse: return " respuesta"
        case .realtimeData: return " pulso en vivo"
        case .realtimeRawData: return " datos crudos"
        case .historicalData: return " historial"
        case .event, .relativePuffinEvents, .puffinEventsFromStrap: return " evento"
        case .metadata, .puffinMetadata: return " metadatos"
        case .consoleLogs: return " logs"
        case .realtimeImuStream: return " IMU en vivo"
        case .historicalImuStream: return " IMU historial"
        default: return ""
        }
    }
}
