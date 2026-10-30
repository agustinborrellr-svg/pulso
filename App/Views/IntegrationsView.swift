import SwiftUI
import AuthenticationServices
import PulsoFeatures
import PulsoIntegrations

/// Apple Health, Strava, heart-rate broadcast and file exports.
struct IntegrationsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var strava: StravaService
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var connecting = false

    var body: some View {
        Form {
            Group {
            if let status = model.importStatus {
                Section { Label(status, systemImage: "info.circle").font(.footnote) }
            }

            // Apple Health
            Section {
                Toggle(isOn: Binding(get: { model.profile.healthKitEnabled }, set: { v in
                    var p = model.profile
                    p.healthKitEnabled = v
                    model.saveProfile(p)
                })) {
                    Label("Conectar con Apple Salud", systemImage: "heart.text.square")
                }
                if model.profile.healthKitEnabled {
                    settingToggle("Guardar mis entrenos en Salud", \.healthWorkouts)
                    settingToggle("Traer entrenos de otras apps", \.healthImport)
                    Button("Enviar datos ahora") { model.exportToHealthIfEnabled() }
                    Button("Importar ahora (entrenos y ECG del Apple Watch)") {
                        model.importExternalIfDue(force: true)
                        model.importAppleWatchECGs()
                    }
                }
            } header: {
                Text("Apple Salud")
            } footer: {
                Text("Pulso envía FC, FC en reposo, VFC, respiración, SpO₂, fases de sueño y entrenos completos con su pulso. Y lee los entrenos que registran Garmin, Strava, Nike, Peloton, apps de gimnasio… (todo lo que llegue a Salud) para sumarlos a tu día.")
            }

            // Strava
            Section {
                if strava.connected {
                    LabeledContent("Cuenta", value: strava.athleteName ?? "Conectada")
                    settingToggle("Subir mis entrenos automáticamente", \.stravaAutoUpload)
                    settingToggle("Importar actividades de Strava", \.stravaImport)
                    Button("Sincronizar ahora") { model.importExternalIfDue(force: true) }
                    Button("Desconectar Strava", role: .destructive) {
                        Task { await strava.disconnect() }
                    }
                } else if strava.credentials.isComplete {
                    Button {
                        connect()
                    } label: {
                        HStack {
                            Spacer()
                            Text(connecting ? "Conectando…" : "Conectar con Strava").font(.headline)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color(red: 0.99, green: 0.32, blue: 0.0))
                    .foregroundStyle(.white)
                    .disabled(connecting)
                    DisclosureGroup("Avanzado") {
                        NavigationLink("Usar mi propia app de la API de Strava") { StravaSetupView(strava: strava) }
                    }
                } else {
                    // Without a Strava subscription there is no API: Apple Health is the bridge, both ways.
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Sin suscripción: a través de Apple Salud", systemImage: "heart.text.square")
                            .font(.subheadline.weight(.semibold))
                        Text("1. Arriba, activa «Conectar con Apple Salud».")
                        Text("2. En la app de Strava: Ajustes → Aplicaciones, servicios y dispositivos → Salud, y activa compartir y recibir actividades.")
                        Text("3. Listo: tus entrenos de Strava llegan a Pulso y los de Pulso a Strava, sin duplicarse.")
                    }
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.vertical, 4)
                    if !model.profile.healthKitEnabled {
                        Button {
                            var p = model.profile
                            p.healthKitEnabled = true
                            model.saveProfile(p)
                            model.health.requestAuthorization { _ in }
                        } label: {
                            Label("Activar Apple Salud", systemImage: "heart.fill")
                        }
                    }
                    if UIApplication.shared.canOpenURL(URL(string: "strava://")!) {
                        Button {
                            UIApplication.shared.open(URL(string: "strava://")!)
                        } label: {
                            Label("Abrir la app de Strava", systemImage: "arrow.up.forward.app")
                        }
                    }
                    DisclosureGroup("Avanzado (suscriptores de Strava)") {
                        NavigationLink("Conectar con la API de Strava") { StravaSetupView(strava: strava) }
                    }
                }
                if let s = strava.status { Text(s).font(.caption).foregroundStyle(Theme.secondary) }
            } header: {
                Text("Strava")
            } footer: {
                Text(strava.connected ? "Los entrenos se suben como archivo FIT con tu pulso segundo a segundo, esfuerzo y calorías. Las actividades que grabes con otros dispositivos se importan y se combinan con los datos de la pulsera sin duplicarse."
                     : strava.credentials.isComplete ? "Toca «Conectar con Strava»: se abre la app de Strava (o su web si no la tienes), pulsas «Autorizar» y vuelves solo a Pulso."
                     : "Strava solo abre su API a suscriptores. Con Apple Salud funciona igual sin pagar; siempre puedes exportar un entreno en FIT y subirlo en strava.com.")
            }

            // Broadcast
            Section {
                settingToggle("Emitir mi pulso como pulsómetro", \.hrBroadcast)
                if model.settings.hrBroadcast {
                    LabeledContent("Estado", value: model.broadcastStatus)
                }
            } header: {
                Text("Otras apps y máquinas")
            } footer: {
                Text("El iPhone aparece como «Pulso HR», un pulsómetro Bluetooth estándar: Zwift, Peloton, Kinomap, cintas y bicis del gimnasio, ciclocomputadores y cualquier app que lea pulsómetros pueden usar tu pulsera. Funciona mejor con Pulso abierta.")
            }

            Section {
                NavigationLink {
                    ExportHelpView()
                } label: {
                    Label("Garmin Connect, TrainingPeaks, Intervals.icu…", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Archivos")
            }
                    }
            .listRowBackground(Theme.card)
        }
        .pulsoList()
        .pulsoTitle("Conexiones")
    }

    private func settingToggle(_ title: String, _ key: WritableKeyPath<FeatureSettings, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { model.settings[keyPath: key] }, set: { v in
            var s = model.settings
            s[keyPath: key] = v
            model.saveSettings(s)
        }))
    }

    private func connect() {
        connecting = true
        // With the Strava app installed, authorise there (already logged in). It comes back through
        // pulso://localhost/strava, handled in PulsoApp.onOpenURL.
        if UIApplication.shared.canOpenURL(URL(string: "strava://")!) {
            UIApplication.shared.open(strava.appAuthorizeURL) { opened in
                if !opened { webConnect() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { connecting = false }
            }
            return
        }
        webConnect()
    }

    private func webConnect() {
        connecting = true
        Task {
            defer { connecting = false }
            do {
                let url = try await webAuth.authenticate(using: strava.authorizeURL, callbackURLScheme: StravaClient.callbackScheme,
                                                         preferredBrowserSession: .ephemeral)
                await strava.complete(callback: url)
                if strava.connected { model.importExternalIfDue(force: true) }
            } catch {
                strava.status = "Conexión cancelada"
            }
        }
    }
}

/// One-time setup of the user's own Strava API application.
struct StravaSetupView: View {
    @ObservedObject var strava: StravaService
    @Environment(\.dismiss) private var dismiss
    @State private var clientID = ""
    @State private var secret = ""

    var body: some View {
        Form {
            Group {
            Section {
                step(1, "Abre strava.com/settings/api en el navegador (con tu cuenta de Strava).")
                step(2, "Crea una aplicación: nombre «Pulso», categoría «Data Importer», web «http://localhost».")
                step(3, "En «Authorization Callback Domain» escribe: localhost")
                step(4, "Copia aquí el «Client ID» y el «Client Secret».")
                Link(destination: URL(string: "https://www.strava.com/settings/api")!) {
                    Label("Abrir strava.com/settings/api", systemImage: "safari")
                }
            } header: {
                Text("Pasos (5 minutos, solo una vez)")
            }
            Section {
                TextField("Client ID", text: $clientID).keyboardType(.numberPad)
                SecureField("Client Secret", text: $secret)
            } footer: {
                Text("Se guardan en el llavero del iPhone, nunca salen de él salvo para hablar con Strava.")
            }
            Section {
                Button("Guardar") {
                    strava.saveCredentials(clientID: clientID, clientSecret: secret)
                    dismiss()
                }
                .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty || secret.trimmingCharacters(in: .whitespaces).isEmpty)
            }
                    }
            .listRowBackground(Theme.card)
        }
        .pulsoList()
        .pulsoTitle("Configurar Strava")
        .onAppear {
            clientID = strava.credentials.clientID
            secret = strava.credentials.clientSecret
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.caption.bold()).frame(width: 22, height: 22).background(Theme.strain, in: Circle())
            Text(text).font(.subheadline)
        }
    }
}

struct ExportHelpView: View {
    var body: some View {
        List {
            Group {
            Text("Abre cualquier entreno (Inicio → Esfuerzo → toca el entreno) y pulsa «Exportar FIT / TCX». Puedes enviarlo a Garmin Connect, TrainingPeaks, Intervals.icu, Runalyze, Final Surge o guardarlo en Archivos.")
            Text("FIT es el formato nativo de Garmin y el que mejor importan todas estas plataformas. TCX es una alternativa en texto.")
            Text("Para exportar todos tus datos (días, entrenos y cada segundo), usa Más → Datos → Preparar exportación CSV.")
                    }
            .listRowBackground(Theme.card)
        }
        .pulsoList()
        .font(.subheadline)
        .pulsoTitle("Exportar entrenos")
    }
}
