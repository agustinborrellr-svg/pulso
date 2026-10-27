import SwiftUI
import WhoopProtocol

/// Tools for the pilot strap: raw frame capture (to reverse-engineer unknown streams such as the
/// MG's ECG), haptic waveform tester and connection details.
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
                Button("Preparar archivo") {
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
                Text("Guarda lo que envía la pulsera que Pulso no entiende todavía (por ejemplo el ECG de una MG). El archivo sirve para descifrar el formato y activar la función.")
            }

            Section {
                Stepper("Efecto A: \(effectA)", value: $effectA, in: 1...255)
                Stepper("Efecto B: \(effectB)", value: $effectB, in: 0...255)
                Stepper("Repeticiones: \(loops)", value: $loops, in: 1...10)
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
                Text("Prueba otras formas de onda de la pulsera. La pareja 47/152 es la de las notificaciones normales de la pulsera. Solo hace vibrar: no cambia nada en la pulsera.")
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

            Section("Pulsera") {
                LabeledContent("Estado", value: "\(model.strapState)")
                LabeledContent("Modelo", value: model.identity.isMG ? "MG" : "5.0")
                LabeledContent("Hardware", value: model.identity.hardware.isEmpty ? "–" : model.identity.hardware)
                LabeledContent("Firmware", value: model.identity.firmware.isEmpty ? "–" : model.identity.firmware)
                NavigationLink("Registro de conexión") { ConnectionLogView() }
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
