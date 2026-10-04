import SwiftUI
import UniformTypeIdentifiers
import PulsoStore
import PulsoAnalytics

struct MoreView: View {
    @EnvironmentObject var model: AppModel
    @State private var importing = false
    @State private var exportURLs: [URL] = []
    @State private var confirmErase = false
    @State private var confirmForget = false
    @State private var alarmOn = false
    @State private var alarmTime = Date()

    var body: some View {
        NavigationStack {
            List {
                strapSection
                Section("Tú") {
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
                    Toggle(isOn: $alarmOn) { Label("Despertador por vibración", systemImage: "alarm") }
                    if alarmOn {
                        DatePicker("Hora", selection: $alarmTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Despertador")
                } footer: {
                    Text("La pulsera vibra a la hora indicada (función experimental en 5.0) y el iPhone te avisa también como respaldo.")
                }
                .onChange(of: alarmOn) { _, v in model.saveAlarm(enabled: v, time: alarmTime) }
                .onChange(of: alarmTime) { _, t in if alarmOn { model.saveAlarm(enabled: true, time: t) } }

                Section {
                    Toggle(isOn: Binding(get: { model.profile.healthKitEnabled }, set: { v in
                        var p = model.profile
                        p.healthKitEnabled = v
                        model.saveProfile(p)
                    })) {
                        Label("Enviar a Apple Salud", systemImage: "heart.text.square")
                    }
                    if model.profile.healthKitEnabled {
                        Button("Exportar ahora") { model.exportToHealthIfEnabled() }
                    }
                } header: {
                    Text("Apple Salud")
                } footer: {
                    Text("FC, FC en reposo, VFC (SDNN), respiración, SpO₂, fases de sueño y energía de entrenos.")
                }

                dataSection

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
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Más")
            .onAppear {
                alarmOn = model.alarmEnabled
                alarmTime = model.alarmTime
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                if case .success(let url) = result { model.importWhoopCSV(from: url) }
            }
        }
    }

    // MARK: Strap

    private var strapSection: some View {
        Section {
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
            LabeledContent("Segundos guardados", value: "\(model.rawSampleCount)")

            Button {
                model.syncNow()
            } label: {
                Label("Sincronizar ahora", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!model.strapState.isConnected)
            Button {
                model.pairNew()
            } label: {
                Label(model.strap.hasSavedStrap ? "Emparejar otra pulsera" : "Buscar pulsera", systemImage: "magnifyingglass")
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
    }

    // MARK: Data

    private var dataSection: some View {
        Section {
            Button {
                importing = true
            } label: {
                Label("Importar historial de WHOOP (CSV)", systemImage: "square.and.arrow.down")
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
            Text("Todo se guarda solo en tu iPhone. Para importar, exporta tus datos desde la app de WHOOP y elige physiological_cycles.csv: sirve para que tus líneas base estén listas desde el primer día.")
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
        .background(Theme.background.ignoresSafeArea())
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
                step(4, "Empareja con Pulso", "En Más → Pulsera, pulsa «Buscar pulsera» y acepta la solicitud de emparejamiento Bluetooth de iOS.")
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
            item("Privacidad", "Sin cuentas, sin servidores, sin analítica. Tus datos no salen del iPhone salvo que los exportes tú.")
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
                        model.pairNew()
                        onDone()
                    }
                } label: {
                    Text(page < 2 ? "Siguiente" : "Buscar mi pulsera")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.green)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Theme.background.ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
        .onAppear { profile = model.profile }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "waveform.path.ecg.rectangle.fill").font(.system(size: 72)).foregroundStyle(Theme.green)
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
                Text("Antes de emparejar").font(.title2.bold())
                Label("Desvincula la pulsera de la app de WHOOP (solo admite un emparejamiento).", systemImage: "1.circle.fill")
                Label("En Ajustes → Bluetooth, omite la WHOOP si aparece.", systemImage: "2.circle.fill")
                Label("Toca la pulsera varias veces hasta que parpadee en azul.", systemImage: "3.circle.fill")
                Label("Acepta la solicitud de emparejamiento que mostrará iOS.", systemImage: "4.circle.fill")
            }
            .padding(24)
        }
    }
}
