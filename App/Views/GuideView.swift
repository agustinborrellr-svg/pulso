import SwiftUI

/// "Guía de Pulso": a short paged tour of how the app works and how to read each number. Opens once
/// after the welcome screens and is always available in Más.
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page: Int

    static let seenKey = "pulso.guideSeen"

    init(startPage: Int = 0) {
        _page = State(initialValue: startPage)
    }

    struct Page: Identifiable {
        let id: Int
        let symbol: String
        let color: Color
        let kicker: String
        let title: String
        let text: String
        let points: [(String, String)]
    }

    static let pages: [Page] = [
        Page(id: 0, symbol: "waveform.path.ecg", color: Theme.red, kicker: "Pulso en 2 minutos",
             title: "Tu WHOOP, sin la nube",
             text: "Pulso habla directamente con tu pulsera por Bluetooth, guarda cada segundo en tu iPhone y calcula todo aquí: recuperación, esfuerzo, sueño, estrés y entrenos.",
             points: [
                ("lock.shield", "Nada sale del teléfono: ni cuenta, ni servidores, ni la app de WHOOP."),
                ("function", "Cada número tiene su fórmula a la vista: toca cualquier métrica para ver de dónde sale."),
                ("stethoscope", "Son estimaciones de bienestar, no un dispositivo médico."),
             ]),
        Page(id: 1, symbol: "arrow.triangle.2.circlepath", color: Theme.strain, kicker: "Cómo llegan tus datos",
             title: "La pulsera guarda, Pulso descarga",
             text: "La pulsera mide sin parar y guarda varios días aunque el iPhone no esté cerca. Pulso descarga lo nuevo al conectarse, al abrir la app y cada media hora mientras está despierta.",
             points: [
                ("iphone", "Deja Pulso en segundo plano. No la cierres deslizando hacia arriba: así puede seguir conectada."),
                ("antenna.radiowaves.left.and.right", "Bluetooth activado y el iPhone a unos metros. Si te lo dejas, no pierdes nada: se descarga al volver."),
                ("arrow.clockwise", "¿Prisa? Más → Sincronizar ahora. Más → Registro de conexión te dice qué está pasando."),
             ]),
        Page(id: 2, symbol: "hourglass", color: Theme.yellow, kicker: "Los primeros días",
             title: "Pulso aprende cómo eres tú",
             text: "Todo se compara con tu propio normal, no con una media de la población. Por eso al principio hay que esperar un poco.",
             points: [
                ("moon.stars", "4 noches para la primera recuperación."),
                ("chart.line.uptrend.xyaxis", "2 a 4 semanas para que tus líneas base sean finas."),
                ("square.and.arrow.down", "¿Vienes de WHOOP? Importa tu exportación en Más → Importar de WHOOP y empiezas con meses de historial."),
             ]),
        Page(id: 3, symbol: "heart.circle", color: Theme.green, kicker: "Recuperación · 0–100 %",
             title: "¿Cómo de preparado estás hoy?",
             text: "Sale de la noche: tu VFC, tu pulso en reposo, tu respiración y tu temperatura comparados con tu normal.",
             points: [
                ("circle.fill", "Verde (67–100): cuerpo listo, buen día para apretar."),
                ("circle.lefthalf.filled", "Amarillo (34–66): normal; entrena con cabeza."),
                ("circle", "Rojo (0–33): algo te está pasando factura (poco sueño, alcohol, estrés, algo que incubas). Día suave."),
             ]),
        Page(id: 4, symbol: "flame", color: Theme.strain, kicker: "Esfuerzo · 0–21",
             title: "Cuánto has cargado al cuerpo",
             text: "Suma el tiempo que pasas con el pulso alto durante todo el día, entrenos y vida normal. La escala es como la de WHOOP: cada punto cuesta más que el anterior.",
             points: [
                ("figure.walk", "0–9: día ligero o de descanso."),
                ("figure.run", "10–17: entreno normal o día movido."),
                ("bolt.heart", "18–21: muy exigente. En Hoy verás el esfuerzo que te conviene según tu recuperación."),
             ]),
        Page(id: 5, symbol: "moon.zzz", color: Theme.sleep, kicker: "Sueño",
             title: "Lo que dormiste frente a lo que necesitabas",
             text: "La necesidad de sueño sube con el esfuerzo de ayer y con la deuda que arrastras. El rendimiento es lo dormido entre lo necesario.",
             points: [
                ("bed.double", "Fases (ligero, profundo, REM) estimadas con pulso, VFC y movimiento: úsalas como orientación."),
                ("clock.badge.checkmark", "La consistencia mide si te acuestas y levantas a horas parecidas: pesa más de lo que parece."),
                ("moon.haze", "«Me voy a dormir» en Hoy te dice a qué hora acostarte para despertar recuperado."),
             ]),
        Page(id: 6, symbol: "brain.head.profile", color: Theme.red, kicker: "Análisis",
             title: "Patrones que solo salen de tus datos",
             text: "Pulso busca lo que es raro en ti y lo que de verdad te afecta, siempre con su margen de error.",
             points: [
                ("waveform.path", "Coherencia: si tus constantes de anoche encajan con tu patrón. Baja cuando varias se desvían a la vez."),
                ("sparkles", "Previsión de mañana con rango, y un simulador: ¿y si duermo una hora más o no bebo?"),
                ("book.closed", "Hábitos: apunta en el diario (alcohol, cafeína tarde, pantallas…) y con unas semanas verás cuánto te afecta cada uno."),
             ]),
        Page(id: 7, symbol: "cross.case", color: Theme.yellow, kicker: "Avisos de salud",
             title: "Cuando algo no cuadra",
             text: "Si la temperatura, el pulso en reposo y la VFC se salen de lo normal a la vez, Pulso te avisa de que podrías estar incubando algo. Suele adelantarse uno o dos días a los síntomas.",
             points: [
                ("exclamationmark.triangle", "No es un diagnóstico: el alcohol, el calor o un viaje dan señales parecidas."),
                ("bell.badge", "Elige qué avisos quieres en Más → Avisos."),
             ]),
        Page(id: 8, symbol: "alarm", color: Theme.sleep, kicker: "Despertador",
             title: "Te despierta la pulsera, con vibración",
             text: "Puedes poner varias alarmas, con hora distinta cada día de la semana. Si la vibración no te despierta, suena el iPhone.",
             points: [
                ("clock", "Hora fija: vibra a la hora exacta."),
                ("waveform", "Inteligente: dentro de una ventana, vibra cuando estás en sueño ligero."),
                ("iphone.radiowaves.left.and.right", "Para que vibre con el iPhone bloqueado, deja Pulso en segundo plano al acostarte. Doble toque en la pulsera para posponer."),
             ]),
        Page(id: 9, symbol: "figure.run.circle", color: Theme.green, kicker: "En vivo y entrenos",
             title: "Tu pulso en directo",
             text: "En la pestaña En vivo ves el pulso segundo a segundo, tu zona y puedes grabar un entreno, con intervalos guiados por vibración y voz.",
             points: [
                ("figure.mixed.cardio", "Los entrenos se detectan solos; luego puedes cambiarles el deporte."),
                ("arrow.up.right.square", "Se pueden mandar a Apple Salud y a Strava (Más → Conexiones)."),
                ("dot.radiowaves.left.and.right", "La pulsera puede hacer de pulsómetro para otras apps y aparatos de gimnasio."),
             ]),
        Page(id: 10, symbol: "checkmark.seal", color: Theme.green, kicker: "Listo",
             title: "Tres costumbres y ya está",
             text: "Con esto Pulso funciona solo. Puedes volver a esta guía cuando quieras desde Más → Guía de Pulso.",
             points: [
                ("1.circle", "Lleva la pulsera también para dormir: la noche es la mitad de los datos."),
                ("2.circle", "No cierres la app deslizando; ábrela por la mañana para ver tu recuperación."),
                ("3.circle", "Apunta tus hábitos de vez en cuando: es lo que convierte los números en consejos para ti."),
             ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(page + 1) de \(Self.pages.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Button("Cerrar") { dismiss() }
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            TabView(selection: $page) {
                ForEach(Self.pages) { p in
                    GuidePage(page: p).tag(p.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            progress
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            Button {
                if page < Self.pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(page < Self.pages.count - 1 ? "Siguiente" : "Empezar a usar Pulso")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.pages[page].color)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(PulsoBackground())
        .preferredColorScheme(.dark)
        .onDisappear { UserDefaults.standard.set(true, forKey: Self.seenKey) }
    }

    private var progress: some View {
        HStack(spacing: 5) {
            ForEach(Self.pages) { p in
                Capsule()
                    .fill(p.id <= page ? Self.pages[page].color : Theme.cardHighlight)
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: page)
    }
}

private struct GuidePage: View {
    let page: GuideView.Page

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    Circle()
                        .fill(page.color.opacity(0.16))
                        .frame(width: 112, height: 112)
                    Circle()
                        .strokeBorder(page.color.opacity(0.45), lineWidth: 2)
                        .frame(width: 112, height: 112)
                    Image(systemName: page.symbol)
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(page.color)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 6)

                Text(page.kicker.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(page.color)
                Text(page.title)
                    .font(.title.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Text(page.text)
                    .font(.body)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(page.points, id: \.1) { point in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: point.0)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(page.color)
                                .frame(width: 26)
                            Text(point.1)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }
}
