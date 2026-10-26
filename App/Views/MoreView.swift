import SwiftUI
import UniformTypeIdentifiers
import PulsoStore
import PulsoAnalytics
import PulsoFeatures
import PulsoIntegrations

struct MoreView: View {
    @EnvironmentObject var model: AppModel
    @State private var restoring = false
    @State private var exportURLs: [URL] = []
    @State private var backupURL: URL?
    @State private var confirmErase = false
    @State private var confirmForget = false
    @State private var pendingStrap: DiscoveredStrap?
    @State private var confirmDemo = false
    @State private var diagnosticsURL: URL?
    @State private var showGuide = false

    var body: some View {
        NavigationStack {
            List {
                strapSection
                Section("Tú") {
                    Button {
                        showGuide = true
                    } label: {
                        Label("Guía de Pulso: cómo funciona todo", systemImage: "book.pages")
                    }
                    NavigationLink {
                        ProfileEditor(profile: model.profile)
                    } label: {
                        Label("Perfil y objetivos", systemImage: "person.crop.circle")
                    }
                    NavigationLink {
                        JournalEditor()
                    } label: {
                        Label("Diario de hábitos", systemImage: "book.closed")
                    }
                }
                Section {
                    NavigationLink {
                        AlarmsView()
                    } label: {
                        LabeledContent {
                            Text(model.nextAlarm.map { Fmt.clock($0.latest) } ?? "Ninguna")
                        } label: {
                            Label("Despertador", systemImage: "alarm")
                        }
                    }
                    NavigationLink {
                        NotificationsView()
                    } label: {
                        Label("Avisos", systemImage: "bell.badge")
                    }
                    NavigationLink {
                        IntegrationsView(strava: model.strava)
                    } label: {
                        Label("Conexiones: Salud, Strava y más", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    NavigationLink {
                        ECGListView()
                    } label: {
                        Label("Electrocardiograma", systemImage: "waveform.path.ecg.rectangle")
                    }
                    Picker(selection: Binding(get: { model.settings.doubleTap }, set: { v in
                        var s = model.settings
                        s.doubleTap = v
                        model.saveSettings(s)
                    })) {
                        ForEach(DoubleTapAction.allCases, id: \.self) { Text($0.label).tag($0) }
                    } label: {
                        Label("Doble toque en la pulsera", systemImage: "hand.tap")
                    }
                    if model.settings.doubleTap == .toggleWorkout {
                        Picker(selection: Binding(get: { model.settings.quickSport }, set: { v in
                            var s = model.settings
                            s.quickSport = v
                            model.saveSettings(s)
                        })) {
                            ForEach(SportCatalog.names, id: \.self) { Text($0).tag($0) }
                        } label: {
                            Label("Deporte del doble toque", systemImage: "figure.run")
                        }
                    }
                } header: {
                    Text("Funciones")
                } footer: {
                    Text("Si suena una alarma, el doble toque la pospone o la apaga.")
                }

                dataSection

                Section {
                    Toggle(isOn: Binding(get: { model.settings.labEnabled }, set: { v in
                        var s = model.settings
                        s.labEnabled = v
                        model.saveSettings(s)
                    })) {
                        Label("Herramientas de laboratorio", systemImage: "flask")
                    }
                    if model.settings.labEnabled {
                        NavigationLink {
                            LabView()
                        } label: {
                            Label("Laboratorio", systemImage: "testtube.2")
                        }
                    }
                } header: {
                    Text("Avanzado")
                } footer: {
                    Text("Para la pulsera de pruebas: captura de tramas, probador de vibraciones y detalles de conexión.")
                }

                Section("Información") {
                    NavigationLink {
                        MethodologyView()
                    } label: {
                        Label("Cómo se calcula cada métrica", systemImage: "function")
                    }
                    Text("Pulso es un proyecto personal no afiliado a WHOOP, Inc. No es un dispositivo médico: todas las métricas son estimaciones de bienestar.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PulsoBackground())
            .navigationTitle("Más")
            .fullScreenCover(isPresented: $showGuide) { GuideView() }

        }
    }

    /// "4 días de datos" rather than a raw count of seconds.
    static func storedText(_ seconds: Int) -> String {
        if seconds <= 0 { return "ninguno" }
        let hours = Double(seconds) / 3600
        if hours < 1 { return "\(max(1, seconds / 60)) min" }
        if hours < 48 { return String(format: "%.0f h", hours) }
        return String(format: "%.0f días", hours / 24)
    }

    // MARK: Strap

    private var strapSection: some View {
        Section {
            NavigationLink {
                DeviceView()
            } label: {
                Label("Configuración del dispositivo", systemImage: "applewatch.side.right")
            }
            HStack {
                Image(systemName: "sensor.tag.radiowaves.forward.fill")
                    .font(.title2)
                    .foregroundStyle(model.strapState.isConnected ? Theme.green : Theme.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.identity.name.isEmpty ? "WHOOP 5.0" : model.identity.name).font(.headline)
                    StrapStatusLine()
                }
            }
            if case .pairingRefused = model.strapState {
                Text("La pulsera no acepta el emparejamiento. Sigue la guía: suele estar todavía vinculada a la app de WHOOP o a un emparejamiento antiguo del iPhone.")
                    .font(.footnote)
                    .foregroundStyle(Theme.yellow)
            }
            if case .unsupported(let msg) = model.strapState {
                Text(msg).font(.footnote).foregroundStyle(Theme.yellow)
            }
            if !model.identity.serial.isEmpty { LabeledContent("Número de serie", value: model.identity.serial) }
            if !model.identity.firmware.isEmpty { LabeledContent("Firmware", value: model.identity.firmware) }
            if !model.identity.hardware.isEmpty {
                LabeledContent("Modelo", value: model.identity.isMG ? "WHOOP MG (\(model.identity.hardware))" : "WHOOP 5.0 (\(model.identity.hardware))")
            }
            LabeledContent("Última sincronización", value: Fmt.relative(model.lastSync))
            LabeledContent("Datos guardados", value: Self.storedText(model.rawSampleCount))

            Button {
                model.syncNow()
            } label: {
                Label("Sincronizar ahora", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!model.strapState.isConnected)
            if model.strapState == .scanning {
                Button {
                    model.stopScan()
                } label: {
                    Label("Buscando… (toca para parar)", systemImage: "stop.circle")
                }
            } else {
                Button {
                    model.scanForStraps()
                } label: {
                    Label(model.strap.hasSavedStrap ? "Emparejar otra pulsera" : "Buscar pulseras cercanas", systemImage: "magnifyingglass")
                }
            }
            if !model.discoveredStraps.isEmpty {
                ForEach(model.discoveredStraps) { s in
                    Button {
                        pendingStrap = s
                    } label: {
                        HStack {
                            Image(systemName: "sensor.tag.radiowaves.forward")
                            VStack(alignment: .leading) {
                                Text(s.name).font(.subheadline.bold())
                                Text(Self.signal(s.rssi)).font(.caption).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Text("Elegir").font(.caption.bold()).foregroundStyle(Theme.green)
                        }
                    }
                }
                Text("Nada se conecta hasta que elijas una. Comprueba el nombre: el número es el de serie de la pulsera.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            if case .pairingRefused = model.strapState {
                Button {
                    model.connect()
                } label: {
                    Label("Reintentar emparejamiento", systemImage: "arrow.clockwise")
                }
            }
            NavigationLink {
                PairingGuideView()
            } label: {
                Label("Guía de emparejamiento", systemImage: "questionmark.circle")
            }
            NavigationLink {
                ConnectionLogView()
            } label: {
                Label("Registro de conexión", systemImage: "list.bullet.rectangle")
            }
            Button {
                model.diagnosticsReport { diagnosticsURL = $0 }
            } label: {
                Label("Preparar diagnóstico", systemImage: "stethoscope")
            }
            if let url = diagnosticsURL {
                ShareLink(item: url) {
                    Label("Enviar diagnóstico", systemImage: "square.and.arrow.up")
                }
            }
            if model.strap.hasSavedStrap {
                Button(role: .destructive) {
                    confirmForget = true
                } label: {
                    Label("Olvidar pulsera", systemImage: "xmark.circle")
                }
                .confirmationDialog("¿Olvidar esta pulsera?", isPresented: $confirmForget) {
                    Button("Olvidar", role: .destructive) { model.forgetStrap() }
                }
            }
        } header: {
            Text("Pulsera")
        }
        .confirmationDialog(pendingStrap.map { "¿Emparejar con \($0.name)?" } ?? "",
                            isPresented: Binding(get: { pendingStrap != nil }, set: { if !$0 { pendingStrap = nil } }),
                            titleVisibility: .visible) {
            Button("Sí, es mi pulsera de pruebas") {
                if let s = pendingStrap { model.chooseStrap(s) }
                pendingStrap = nil
            }
            Button("Cancelar", role: .cancel) { pendingStrap = nil }
        } message: {
            Text("Una WHOOP solo admite un emparejamiento. Asegúrate de que no es la pulsera vinculada a tu cuenta de WHOOP.")
        }
    }

    static func signal(_ rssi: Int) -> String {
        switch rssi {
        case (-60)...: return "Muy cerca"
        case (-75)...: return "Cerca"
        default: return "Lejos"
        }
    }

    // MARK: Data

    private var dataSection: some View {
        Section {
            if model.demoActive {
                Button(role: .destructive) {
                    model.clearDemo()
                } label: {
                    Label("Quitar datos de demostración", systemImage: "sparkles")
                }
            } else {
                Button {
                    if model.rawSampleCount > 0 { confirmDemo = true } else { model.loadDemo() }
                } label: {
                    Label(model.analyzing ? "Preparando demo… \(Int(model.analysisProgress * 100))%" : "Cargar datos de demostración",
                          systemImage: "sparkles")
                }
                .disabled(model.analyzing)
                .confirmationDialog("Ya tienes datos reales. La demo se mezclaría con ellos y para quitarla hay que borrar todo.",
                                    isPresented: $confirmDemo, titleVisibility: .visible) {
                    Button("Cargar igualmente") { model.loadDemo() }
                    Button("Cancelar", role: .cancel) {}
                }
            }
            NavigationLink {
                WhoopImportView()
            } label: {
                Label("Importar de WHOOP (CSV)", systemImage: "square.and.arrow.down")
            }
            Button {
                exportURLs = model.exportFiles()
            } label: {
                Label("Preparar exportación CSV", systemImage: "tablecells")
            }
            if !exportURLs.isEmpty {
                ShareLink(items: exportURLs) {
                    Label("Compartir \(exportURLs.count) archivos", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                backupURL = model.makeBackup()
            } label: {
                Label("Crear copia de seguridad", systemImage: "externaldrive.badge.plus")
            }
            if let url = backupURL {
                ShareLink(item: url) {
                    Label("Guardar copia (Archivos, iCloud Drive…)", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                restoring = true
            } label: {
                Label("Restaurar una copia", systemImage: "arrow.counterclockwise")
            }
            // Its own importer: SwiftUI only honours one .fileImporter per view.
            .fileImporter(isPresented: $restoring, allowedContentTypes: [.data, .item]) { result in
                if case .success(let url) = result { _ = model.stageRestore(from: url) }
            }
            Button {
                model.recompute(fromDay: nil)
            } label: {
                Label(model.analyzing ? "Analizando… \(Int(model.analysisProgress * 100))%" : "Recalcular todo", systemImage: "wand.and.stars")
            }
            .disabled(model.analyzing)
            Picker(selection: Binding(get: { model.profile.rawRetentionDays }, set: { v in
                var p = model.profile
                p.rawRetentionDays = v
                model.saveProfile(p)
            })) {
                Text("30 días").tag(30)
                Text("120 días").tag(120)
                Text("1 año").tag(365)
                Text("Siempre").tag(0)
            } label: {
                Label("Guardar datos por segundo", systemImage: "internaldrive")
            }
            Button(role: .destructive) {
                confirmErase = true
            } label: {
                Label("Borrar todos mis datos", systemImage: "trash")
            }
            .confirmationDialog("Se borrarán todos los datos del iPhone. No se puede deshacer.", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Borrar todo", role: .destructive) { model.eraseEverything() }
            }
        } header: {
            Text("Datos")
        } footer: {
            Text("La demo genera cinco semanas simuladas (noches buenas y malas, entrenos, unos días de «incubar algo») para probar todo sin pulsera. Todo se guarda solo en tu iPhone. La copia de seguridad incluye todo (también cada segundo de datos); guárdala en Archivos o iCloud Drive. Para importar de WHOOP, exporta tus datos desde su app y sube los CSV que quieras (ciclos, sueño, entrenos, diario): verás tu historial y tus líneas base estarán listas desde el primer día.")
        }
    }
}

struct ProfileEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var profile: Profile
    @State private var manualMax = false

    var body: some View {
        Form {
            Section("Datos personales") {
                TextField("Nombre", text: $profile.name)
                Stepper("Año de nacimiento: \(String(profile.birthYear))", value: $profile.birthYear, in: 1930...2015)
                Picker("Sexo", selection: $profile.sex) {
                    Text("Hombre").tag(Sex.male)
                    Text("Mujer").tag(Sex.female)
                    Text("Otro").tag(Sex.other)
                }
                Stepper("Peso: \(Int(profile.weightKg)) kg", value: $profile.weightKg, in: 35...200, step: 1)
                Stepper("Altura: \(Int(profile.heightCm)) cm", value: $profile.heightCm, in: 120...230, step: 1)
            }
            Section {
                Toggle("FC máxima manual", isOn: $manualMax)
                if manualMax {
                    Stepper("FC máx: \(profile.maxHROverride ?? 185) lpm",
                            value: Binding(get: { profile.maxHROverride ?? 185 }, set: { profile.maxHROverride = $0 }),
                            in: 120...230)
                }
            } header: {
                Text("Zonas cardiacas")
            } footer: {
                Text("Si no la fijas, se estima con la fórmula de Tanaka (208 − 0,7 × edad) y sube automáticamente si registras un pico mayor.")
            }
            Section {
                Toggle("Estimar el ciclo menstrual", isOn: $profile.cycleTracking)
            } header: {
                Text("Ciclo")
            } footer: {
                Text("Usa el cambio de temperatura de la piel por la noche para estimar la fase y el próximo periodo. Es orientativo: no sirve como anticonceptivo.")
            }
            Section {
                Stepper(String(format: "Necesidad base: %.1f h", profile.sleepNeedHours), value: $profile.sleepNeedHours, in: 6...10, step: 0.25)
            } header: {
                Text("Sueño")
            } footer: {
                Text("Cada noche se ajusta con el esfuerzo del día, la deuda acumulada y las siestas.")
            }
        }
        .navigationTitle("Perfil")
        .onAppear { manualMax = profile.maxHROverride != nil }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    var p = profile
                    if !manualMax { p.maxHROverride = nil }
                    model.saveProfile(p)
                    dismiss()
                }
            }
        }
    }
}

struct JournalEditor: View {
    @EnvironmentObject var model: AppModel
    @State private var day = DayKey.string(Date())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { day = DayKey.shift(day, days: -1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(Fmt.dayTitle(day)).font(.headline)
                    Spacer()
                    Button { day = DayKey.shift(day, days: 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(day >= DayKey.string(Date()))
                }
                .tint(.white)
                Text("Marca lo que hiciste este día. Tras 5 días con y sin cada hábito, Pulso te dirá cuánto cambia tu recuperación del día siguiente.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                FlowChips(day: day, entries: model.journal(for: day))
            }
            .padding()
        }
        .background(PulsoBackground())
        .navigationTitle("Diario")
    }
}

struct PairingGuideView: View {
    var body: some View {
        List {
            Section {
                step(1, "Libera la pulsera", "La WHOOP 5.0 solo admite un emparejamiento a la vez. En la app de WHOOP, desvincula la pulsera (o desinstala la app).")
                step(2, "Olvida el emparejamiento antiguo", "iPhone → Ajustes → Bluetooth → toca (i) junto a la WHOOP → Omitir dispositivo.")
                step(3, "Modo emparejamiento", "Toca la pulsera varias veces seguidas hasta que los LED parpadeen en azul.")
                step(4, "Empareja con Pulso", "En Más → Pulsera, pulsa «Buscar pulseras cercanas», elige la tuya por su nombre y acepta la solicitud de emparejamiento de iOS.")
            } header: {
                Text("Primera vez")
            }
            Section {
                Text("Pulso ajusta el reloj de la pulsera al conectar (sin reloj, la pulsera no guarda datos), descarga el historial que guarda (hasta ~14 días) y solo entonces confirma cada bloque. Nunca envía comandos de borrado, firmware ni reinicio.")
                Text("Mantén Pulso abierta en segundo plano: iOS reconecta solo cuando la pulsera está cerca y la app sincroniza al abrirla o cuando la pulsera envía eventos.")
                Text("Si falla: apaga y enciende el Bluetooth, repite el paso 2 y 3, y pulsa «Reintentar emparejamiento».")
            } header: {
                Text("Bueno saber")
            }
            .font(.footnote)
        }
        .navigationTitle("Emparejar")
    }

    private func step(_ n: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Theme.strain, in: Circle())
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ConnectionLogView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(Array(model.log.reversed().enumerated()), id: \.offset) { item in
            Text(item.element).font(.caption.monospaced())
        }
        .navigationTitle("Registro")
    }
}

struct MethodologyView: View {
    var body: some View {
        List {
            item("Datos de la pulsera", "Cada segundo la WHOOP 5.0 guarda FC, intervalos R-R, gravedad y movimiento, temperatura de la piel, SpO₂ (de noche), pasos y su propio estado de sueño. Pulso lo descarga por Bluetooth con el protocolo documentado por la comunidad open source y lo guarda en el iPhone.")
            item("VFC (RMSSD)", "Raíz cuadrática media de las diferencias entre latidos consecutivos (Task Force 1996), tras filtrar artefactos (±20 % de la mediana local). Solo se usan pares de latidos consecutivos reales. El valor nocturno se mide en las ventanas de sueño profundo, como hace WHOOP.")
            item("FC en reposo", "Media de la FC en esas mismas ventanas de sueño profundo (si no hay, el percentil 10 de la noche).")
            item("Respiración", "Arritmia sinusal respiratoria: el ritmo cardiaco se acelera al inspirar. Se busca la frecuencia dominante (0,1–0,5 Hz) del tacograma R-R remuestreado a 4 Hz.")
            item("Detección y fases del sueño", "Quietud (acelerómetro), caída de la FC y el propio estado de sueño de la pulsera detectan el periodo. Las fases (despierto/ligero/profundo/REM) salen de FC, variabilidad de FC, VFC y movimiento por minuto, suavizadas con un modelo oculto de Markov (Viterbi).")
            item("Recuperación", "Puntuación z robusta frente a tus propias líneas base (mediana y MAD de las últimas noches): VFC 50 %, FC reposo 20 %, sueño 20 %, respiración 5 %, temperatura 5 %, pasada por una curva logística a 0–100 %. Necesita 4 noches para calibrar. Verás el peso de cada factor en «Por qué».")
            item("Esfuerzo (0–21)", "Carga cardiovascular por minuto según tu reserva de FC (Karvonen): 0 por debajo del 40 %, y +1 por cada 10 % adicional (estilo Edwards). Se comprime con un logaritmo: cuesta mucho más pasar de 17 a 18 que de 4 a 5.")
            item("Calorías", "Metabolismo basal Mifflin-St Jeor en reposo y ecuación de Keytel (2005) cuando la FC indica actividad.")
            item("Estrés (0–3)", "Ventanas de 5 minutos en reposo y despierto, fuera de entrenos: FC y VFC frente a tu referencia de calma de las últimas 2 semanas.")
            item("Necesidad de sueño", "Tu base (8 h por defecto) + minutos extra por esfuerzo alto + la mitad de la deuda reciente − siestas.")
            item("VO₂máx", "Estimación de Uth (15,3 × FC máx / FC reposo). Orientativa.")
            item("Carga de entrenamiento", "Cada día se convierte el esfuerzo en carga cardiovascular. La carga aguda es la media ponderada de 7 días (fatiga) y la crónica la de 42 días (forma). Su cociente indica si subes carga a buen ritmo (0,8–1,3) o demasiado deprisa (más de 1,5).")
            item("Posible enfermedad", "Se avisa cuando varias constantes de la noche se salen a la vez de tu línea base: temperatura +0,5 °C o más, FC en reposo +4 lpm o más, respiración +0,8 rpm, VFC muy baja o SpO₂ 2 puntos por debajo. Suele adelantarse 1–2 días a los síntomas.")
            item("Alarma inteligente", "En la ventana elegida, Pulso descarga cada 2–3 minutos lo último de la pulsera y despierta cuando detecta sueño ligero: movimiento, la pulsera te marca despierto, el pulso sube sobre el mínimo de la noche o se vuelve irregular (REM).")
            item("Hora de acostarse", "Tu necesidad de esta noche dividida entre tu eficiencia de sueño habitual, más 15 minutos para dormirte, contada hacia atrás desde tu próxima alarma (o tu hora habitual de despertar).")
            item("ECG", "Detección de latidos tipo Pan-Tompkins, latido medio para medir la calidad de la señal y buscar la onda P, e irregularidad de los intervalos R-R. Ritmo irregular = intervalos caóticos y sin onda P. Es orientativo y no sustituye a un médico.")
            item("Privacidad", "Sin cuentas, sin servidores, sin analítica. Tus datos no salen del iPhone salvo que los exportes tú o conectes Strava (solo se envían los entrenos).")
        }
        .navigationTitle("Metodología")
    }

    private func item(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(Theme.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    let onDone: () -> Void
    @State private var page = 0
    @State private var profile = Profile()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TabView(selection: $page) {
                    welcome.tag(0)
                    profileForm.tag(1)
                    pairing.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                Button {
                    if page < 2 {
                        withAnimation { page += 1 }
                    } else {
                        model.saveProfile(profile)
                        model.hasOnboarded = true
                        onDone()
                    }
                } label: {
                    Text(page < 2 ? "Siguiente" : "Empezar")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.red)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(PulsoBackground())
        }
        .preferredColorScheme(.dark)
        .onAppear { profile = model.profile }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            Image("Logo")
                .resizable()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                .shadow(color: Theme.red.opacity(0.4), radius: 20)
            Text("Pulso").font(.largeTitle.bold())
            Text("Tu WHOOP 5.0, sin la nube. Recuperación, esfuerzo, sueño y estrés calculados en tu iPhone, con cada fórmula a la vista.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var profileForm: some View {
        Form {
            Section {
                TextField("Nombre", text: $profile.name)
                Stepper("Año de nacimiento: \(String(profile.birthYear))", value: $profile.birthYear, in: 1930...2015)
                Picker("Sexo", selection: $profile.sex) {
                    Text("Hombre").tag(Sex.male)
                    Text("Mujer").tag(Sex.female)
                    Text("Otro").tag(Sex.other)
                }
                Stepper("Peso: \(Int(profile.weightKg)) kg", value: $profile.weightKg, in: 35...200)
                Stepper("Altura: \(Int(profile.heightCm)) cm", value: $profile.heightCm, in: 120...230)
            } header: {
                Text("Sobre ti")
            } footer: {
                Text("Se usa para zonas cardiacas, calorías y VO₂máx. Puedes cambiarlo luego.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var pairing: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Emparejar, cuando quieras").font(.title2.bold())
                Text("Pulso no se conecta a ninguna pulsera por su cuenta. Cuando quieras emparejar, ve a Más → Pulsera → Buscar pulseras cercanas y elige la tuya de la lista.")
                    .foregroundStyle(Theme.secondary)
                Label("Usa una pulsera que no esté vinculada a tu cuenta de WHOOP (solo admite un emparejamiento).", systemImage: "1.circle.fill")
                Label("En Ajustes → Bluetooth, omite la WHOOP si aparece.", systemImage: "2.circle.fill")
                Label("Toca la pulsera varias veces hasta que parpadee en azul.", systemImage: "3.circle.fill")
                Label("Elígela en la lista y acepta la solicitud de emparejamiento de iOS.", systemImage: "4.circle.fill")
            }
            .padding(24)
        }
    }
}
