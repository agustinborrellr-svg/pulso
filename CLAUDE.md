# Pulso — contexto para Claude Code

Este proyecto viene de una sesión en la nube de Claude (Cowork). Este archivo es el relevo:
léelo entero antes de hacer nada.

## Quién es el usuario y cómo trabajar con él

- Gus. Habla en **castellano coloquial**. Quiere resultados terminados, sin rodeos ni explicaciones de más.
- Quiere que trabajes **de forma autónoma** hasta tener algo que funcione, sin pedir permiso para cada paso.
- Tiene **PC con Windows + iPhone** y una **WHOOP 5.0**. No tiene Mac.
- Cuenta de GitHub: `agustinborrellr-svg`. Repositorio privado ya creado y **vacío**: `agustinborrellr-svg/pulso`.

## Qué es Pulso

App de iPhone (SwiftUI) que habla directamente con una WHOOP 5.0 / MG por Bluetooth, descarga los
datos por segundo, los guarda en SQLite local y calcula todas las métricas en el teléfono:
recuperación, esfuerzo, sueño con fases, VFC, FC en reposo, respiración, SpO₂, temperatura,
estrés, calorías, VO₂máx y entrenos. No usa la app ni la nube de WHOOP. Uso personal.

```
App/                    App iOS (CoreBluetooth, HealthKit, Swift Charts, SwiftUI)
  BLE/StrapManager.swift    conexión, emparejamiento, reloj, descarga con ACK, pulso en vivo
  Model/AppModel.swift      estado, análisis en segundo plano, import/export, alarma
  Views/                    Hoy, Sueño, Tendencias, En vivo, Más (perfil, datos, guía)
Packages/PulsoKit/      Núcleo Swift puro, con tests
  WhoopProtocol/            tramas, CRC8/16/32, comandos, decodificadores, sesión de descarga
  PulsoStore/               SQLite (muestras por segundo + resúmenes diarios)
  PulsoAnalytics/           detección y fases de sueño, VFC, respiración, recuperación, esfuerzo…
Pulso.xcodeproj         generado con XcodeGen desde project.yml (no editar a mano; regenerar)
.github/workflows/ios.yml  compila en macOS, publica Pulso.ipa en Releases, deja informe en rama ci-status
docs/PROTOCOLO.md       referencia del protocolo BLE de la WHOOP 5.0
```

## Estado (2026-10-25)

- Versión 1.1 en marcha: despertador inteligente, avisos, Strava, Apple Salud bidireccional, pulsómetro
  para otras apps, intervalos con vibración y voz, carga de entrenamiento, aviso de enfermedad, ciclo,
  widgets, Live Activity, Siri/Atajos, copia de seguridad, laboratorio y ECG preparado para la MG.
- Núcleo: 88 tests en verde con Swift 6.2 en Linux (WSL Ubuntu 24.04 en el PC de Gus:
  `wsl -d Ubuntu-24.04 -u root -- bash -c "cd /mnt/c/Users/agust/Pulso/Packages/PulsoKit && swift test --scratch-path /root/pk-build"`).
  FIT validado con `fitdecode`, TCX con un parser XML, PDF del ECG renderizado y revisado.
- Toda la lógica nueva vive en PulsoKit (probada). La capa iOS (App/, Widgets/) solo orquesta y
  pinta; se compila en GitHub Actions (macOS) y la primera pasada puede tener errores de API.
- Gus se va a comprar **otra pulsera para el piloto** (miedo a que le baneen la cuenta de WHOOP con
  la principal). No le pidas emparejar su pulsera principal.
- `Pulso.xcodeproj` se regenera en CI con XcodeGen (artefacto `xcodeproj`); tras un build verde,
  bájalo con `gh run download -n xcodeproj` y súbelo al repo para que abra directo en Xcode.

## Estado (2026-10-26)

- Instalar en el iPhone está **bloqueado por Apple**: desde el 12–13 oct rechaza los inicios de sesión
  de los instaladores gratuitos (Sideloadly, AltStore, Impactor: SRP -80045/-80046/403). Gus tiene
  instalados iTunes (web), iCloud 7.21 (se cierra al abrir), Sideloadly e Impactor 2.7.2. Opciones:
  esperar a que Impactor/Sideloadly lo arreglen, un Mac con Xcode, o cuenta de desarrollador + TestFlight.
- Nuevo: modo demo (35 días), capturas automáticas en CI (commit con `[capturas]` → rama `ci-shots`),
  plan B de emparejamiento (modo secuencial OpenStrap + cambio automático), diagnóstico, «Me voy a dormir»,
  intents de hábitos, icono rojo (`docs/design/make_icon.py`).
- **PulsoIntelligence** (`docs/INTELIGENCIA.md`): desviación (Mahalanobis, coherencia, deuda), respuesta a
  la carga, análisis por entreno (FCR, deriva, reserva), ritmo (SRI), hábitos con IC y modelo predictivo
  con validación cronológica y simulador. Pestaña «Análisis».
- Modelo ajustado: deuda de sueño como arrastre decreciente, necesidad acotada, recuperación más suave,
  esfuerzo cotidiano en días de descanso. 87 tests en verde.
- Seguridad: la app **nunca** se conecta sola a una pulsera; buscar lista y pide confirmación.

## Estado (2026-10-26, revisión en Mac)

- Revisado en Xcode 27.1: núcleo 91 tests en verde, app compila para simulador. Protocolo contrastado con
  noop / OpenStrap / whoop-rs: corregidos el byte de repeticiones de las vibraciones, la validez del pulso en
  directo (byte 9 = nº de R-R), la temperatura i16 y la lista de opcodes bloqueados (faltaban FORGET_BONDS,
  SET_READ_POINTER, LOCK_DEVICE…). Alarma fija ahora mantiene la app viva 30 min antes; entitlement
  time-sensitive añadido; demo ya no se exporta a Salud. Detalle y pendientes en `docs/REVISION-2026-10-26.md`.

## Estado (2026-10-26, tras la revisión)

- Alarmas con hora distinta por día de la semana (`AlarmConfig.dayTimes`, editor «Hora distinta cada día»).
  Las fijas también mantienen la conexión de noche (10 h antes) para que vibre la pulsera.
- GET_DATA_RANGE con `00`; desfase de adaptación desde 12 semanas (test de permutaciones; confianza
  baja hasta 26). 94 tests en verde.
- Instalación: Sideloadly 0.71.1 → -80046; iloader 2.4.0 pasa la contraseña pero el 2FA da 403 con todos
  los anisette. Vía gratis en Windows bloqueada: Mac de un amigo (`COMPILAR_EN_MAC.md`) o cuenta de pago.

## Estado (2026-10-27)

- Importación de WHOOP reescrita (`WhoopExport` en Interop.swift): CSV en español/inglés, ciclos, sueño,
  entrenos (origen `.whoop`) y diario, todos opcionales; probado con la exportación real de Gus (140 días,
  247 entrenos). Pantalla Más → Importar de WHOOP. Los días importados se ven en la app.
- Guía de Pulso (`GuideView`, 11 páginas): tras la bienvenida y en Más.
- Descarga automática cada 30 min con la pulsera conectada (y aprovechando el pulso en directo).
- `MetricsTruthTests`: métricas contra la fisiología conocida de la demo (FC reposo ±0,3 lpm). 101 tests.
- AccentColor era casi negro (botones invisibles en hojas): ahora blanco. Capturas en es_ES y sin
  pedir permisos.

## Estado (2026-10-27, interfaz nueva)

- Interfaz rehecha con el estilo de las capturas de referencia de Gus (WHOOP): fondo pizarra, títulos en
  mayúsculas espaciadas, tarjetas, flechas ▲▼ vs tu media. Componentes en `App/Design/PulsoUI.swift`.
- Pestañas: Inicio (`Home/HomeView`: diales, panel personalizable, esfuerzo-recuperación, estrés, coach),
  Salud (`Health/HealthView`: Edad Pulso, ritmo, monitor de salud, hábitos), Análisis, En vivo, Más.
- Detalles: `RecoveryDetailView`, `SleepDetailView` (fases seleccionables), `StrainDetailView`,
  `StressMonitorView`, `Trends/TrendDetailView` (S/M/6M, navegación, tocar para leer), `Device/DeviceView`
  + `PairingFlowView`. Lógica probada en PulsoKit: `TrendSeries`, `PulsoAge`.
- Ojo con Swift Charts y ejes categóricos: fijar `.chartXScale(domain:)` o el orden sale mal.

## Estado (2026-10-27, arreglos pasos 1-5)

- Paso 1: SQLite versionado (`PRAGMA user_version` + migraciones), lectura tolerante (TolerantDecoding.swift),
  `DayEngine.derivedVersion` (recalcula al cambiar algoritmos), ciclo abierto hasta dormir (WHOOP), posponer.
- Paso 2: fases sin forzar + `StageConfidence` con motivos; siestas/sueño de día con pregunta (aviso + tarjeta),
  decisiones en kv `sleep.decisions`.
- Paso 3: carga TRIMP 7/28; Strava robusto (refresh único, 401, 429, paginación); ECG validado con PhysioNet
  (sens 78 %, esp 96 %; `PULSO_ECG_DIR`, descarga con scratchpad physionet.py).
- Paso 4: VO₂ máx (normas), plan semanal, actividad manual, tendencia de Edad Pulso.
- Paso 5 (subido SIN COMPILAR): restyle del resto (pulsoTitle/pulsoList), Análisis con pestañas.
- 27-oct: GitHub Actions dejó de arrancar (facturación / minutos de Mac agotados en repo privado).

## Estado (2026-10-27, noche: «hazlo todo»)

- Repo **público** desde el 27-oct (minutos de Mac agotados en privado). Historial limpiado de logs con UDID.
- **Sin menciones a WHOOP** en la app: la pulsera es «Pulse Band 5.0 / MG» (`Fmt.bandName`). Identificadores internos
  (`WhoopProtocol`, `.whoop`, kv `whoop:`) se quedan. No reintroducir el nombre en textos visibles.
- **Datos que nunca se pierden**: muestras con UPSERT `COALESCE` (una re-descarga parcial no borra valores), datos por
  segundo «Siempre» por defecto (migración 120→0 una vez, kv `migration.retentionForever`), copias automáticas en
  Documents/«Copias de seguridad» (visible en Archivos): diaria ligera ×14, semanal completa ×3, y completa antes de
  importar/restaurar/borrar ×5 (`BackupPolicy`, `AppModel+Backups`). Más → Almacenamiento explica todo.
- **En vivo**: `LiveMetrics` (escaneo 60 s vs calma, Poincaré, coherencia, ortostático, recuperación FC, FC máx,
  `ZoneGuard`, vueltas). UI en `LiveView` + `LiveToolsViews.swift`; historial de tests en kv `live.tests`.
- **Análisis**: `AnalysisTools` (cascada del %, `Relation`, rachas/récords, `MonthlyReport`) + `AnalysisExtras.swift`
  (resumen de hoy, por desbloquear, lo que más te afecta, explorador, calendario, informe PDF).
- **Strava en un toque**: `StravaBuiltIn.swift` vacío en el repo; CI lo rellena con los secretos `STRAVA_CLIENT_ID` /
  `STRAVA_CLIENT_SECRET`. Conecta abriendo la app de Strava (`strava://oauth/mobile/authorize`, vuelve por
  `pulso://localhost/strava`). Credenciales propias en Conexiones → Strava → Avanzado.
  **Oct-2026: Strava cerró su API a suscriptores; Gus no paga.** Camino por defecto = puente Apple Salud (Strava ↔ Salud
  ↔ Pulso) explicado en Conexiones; la API queda en «Avanzado (suscriptores)». Export FIT manual sigue disponible.
- 81 actividades (`SportCatalog`); «Intimidad» nunca se manda a Strava ni a Salud (`Sport.shareable`).
- Sueño de días importados: fases y constantes desde el resumen (`HistoryMerge.summarySleep`).
- Datos de demostración fuera de la UI (solo capturas de CI). 142 tests del núcleo en verde.

## Compilar y dejarlo verde

1. Comprueba que hay Git (`git --version`). Si no hay historial (`git log` falla): `git init -b main`, `git add -A` y un commit.
2. `git remote add origin https://github.com/agustinborrellr-svg/pulso.git` (o `set-url` si ya existe).
3. `git push -u origin main`. La primera vez, Git Credential Manager abre el navegador para iniciar sesión en GitHub.
4. El push lanza el workflow **Compilar Pulso (iOS)**, que tarda unos 10 minutos. Para seguirlo:
   - si hay `gh` CLI: `gh run watch` / `gh run view --log-failed`;
   - si no: espera y haz `git fetch origin ci-status` y luego
     `git show origin/ci-status:status.txt` y `git show origin/ci-status:xcodebuild-errors.txt`.
     El workflow deja ahí el resultado de tests y compilación, los errores y el tamaño del .ipa.
5. Si falla, corrige el código, haz commit y push, y repite hasta `build=success` y `package=success`.
   No toques la lógica de protocolo sin motivo; los errores esperables son de firmas de API de
   SwiftUI, Charts o HealthKit, o de concurrencia con el compilador Swift 6 de Xcode 16. El proyecto
   está en modo Swift 5 con `SWIFT_STRICT_CONCURRENCY: minimal`.
6. El workflow ya ejecuta `xcodegen generate` antes de compilar: no edites el `.pbxproj` a mano.
7. Cuando esté verde, `Pulso.ipa` queda en **Releases → ultima**. Dile a Gus que lo instale con Sideloadly (pasos abajo).

Límite: el plan gratuito da unos 200 minutos de Mac al mes en repos privados. No lances compilaciones a lo loco.

## Instalación en el iPhone (la hace Gus, guíale)

1. iPhone: *Ajustes → Privacidad y seguridad → Modo de desarrollador* → activar y reiniciar.
2. PC: iTunes e iCloud **de la web de Apple** (no de Microsoft Store), y después Sideloadly (sideloadly.io).
3. iPhone conectado por cable → «Confiar». En Sideloadly: arrastrar `Pulso.ipa`, poner su Apple ID y pulsar Start.
   Él escribe la contraseña y el código 2FA. **Nunca le pidas la contraseña.**
4. iPhone: *Ajustes → General → VPN y gestión de dispositivos* → confiar.
5. Activar *Automatic refresh* en Sideloadly (la firma gratuita caduca a los 7 días).

## Riesgo principal: el emparejamiento de la WHOOP 5.0 en iOS

- NOOP 12.0.0 (github.com/ryanbr/noop, la app open source más madura) dice que con la 5.0/MG la
  pulsera **rechaza el handshake de emparejamiento**, nunca recibe hora y las descargas salen vacías.
  Solo funciona el pulso en directo.
- Pulso usa el mismo método que NOOP y que OpenStrap en iOS: escribir el CLIENT_HELLO
  `AA 01 08 00 00 01 E6 71 23 01 91 01 36 3E 5C 8D` en `fd4b0002` **con respuesta** para que iOS
  haga el bond, y después suscribirse a `fd4b0003/4/5/7`, GET_HELLO, SET_CLOCK si la deriva es de 2 s
  o más, y SEND_HISTORICAL_DATA.
- OpenStrap Edge (github.com/OpenStrap/edge, MIT, beta iOS en TestFlight) dice soportar la 5.0. Su
  secuencia «oficial» es: conectar → MTU 247 → bond → esperar 600 ms → suscribir las notificaciones
  **de una en una** → esperar 500 ms → GET_HELLO(145, cuerpo 01; PENDING no es final) → reloj (sin
  escribir si la deriva es menor de 2 s) → GET_ADVERTISING_NAME(141, cuerpo 01) → listo.
  Si en el iPhone de Gus falla el emparejamiento, ese es el primer cambio que hay que probar en
  `StrapManager`.
- La pulsera admite un solo emparejamiento: hay que desvincularla de la app de WHOOP, omitirla en
  *Ajustes → Bluetooth* y ponerla en modo emparejamiento (tocar hasta que el LED parpadee en azul).
- Diagnóstico: en la app, *Más → Registro de conexión* muestra cada paso. Pídele a Gus capturas de esa pantalla.

## Reglas

- Nunca envíes a la pulsera opcodes destructivos. `Opcode.forbidden` en `Commands.swift` bloquea los
  de borrado, firmware, reinicio y configuración persistente; no lo relajes.
- Nunca confirmes un bloque del histórico antes de guardarlo (`OffloadSession` + `persist`).
- No subas secretos al repo. Gus pegó un token de GitHub en la conversación de la nube; recuérdale que lo revoque.
- Referencias útiles del protocolo: `whoop-rs` (tanarchytan), `noop` (docs/PROTOCOL.md),
  `OpenStrap/protocol`, `whoop5-protocol` (Rudra5417).

## Estado (2026-10-30, auditoría integral)

- Auditoría en `docs/AUDITORIA-2026-10-30.md`, informe final A–J en `docs/INFORME-2026-10-30.md`. 185 tests del núcleo en verde.
- Descarga: registros no decodificados se guardan antes del ACK (`undecoded_records`, esquema 2). `derivedVersion` 5.
- Nuevo: `NightStatus` (noche pendiente), siestas con «No dormí» (`SleepDecision.notSleep`), entrenos rechazados
  (kv `workouts.rejected`), monitor fisiológico (`MonitorView`), pruebas en vivo en el modelo (`AppModel+LiveTests`),
  inicio configurable (`HomeWidgets`, kv `pulso.home`), tendencias/calendario (`TrendExplorer`), `MetricGuide`,
  `PulsoPalette` compartida app/widgets, `.scaledFont` (Dynamic Type), `PulseLoader`, `ConnectionStatus`.
- SpO₂ fuera de la recuperación (byte sin confirmar). ECG simulado = «Demostración», sin PDF.
- Nada validado aún con la pulsera física.

## Estado (2026-11-01, funciones tipo WHOOP)

- `Behaviors` (PulsoIntelligence): impacto % en la recuperación de comportamientos automáticos (sueño ≥ mediana, horario
  constante, entreno temprano/tardío, estrés alto, esfuerzo alto) y del diario; desbloqueo con 5 con / 5 sin. `BehaviorsView`.
- `CyclePhases` + `CycleCalendarView` (reglas manuales en kv `cycle.starts` + detección por temperatura).
- `BloodPressure` + `BloodPressureView`: lecturas manuales (kv `bp.readings`), categorías AHA. **Sin estimación inventada.**
- `PeriodAverages`: medias por mes con % de cambio en la vista de tendencias a 6 meses. Checklist en el detalle del ECG.
- Doble toque: acciones nuevas `speakStatus`, `scan`, `webhook` (Home Assistant/IFTTT/ntfy; vibra 1 ok / 3 fallo),
  `shortcut` (notificación que abre `shortcuts://run-shortcut`). Pantalla `DoubleTapView`. Evento de la 5.0 sin confirmar.
- Tests en Linux: `IntelData` (no instanciar XCTestCase para helpers). 195 tests del núcleo.

## Estado (2026-11-01, Edad Pulso con estudios)

- `PulsoAge`: años = ln(RR(valor)/RR(guía)) / 0,085 (Gompertz). Curvas: sueño (Liu 2017, Cappuccio 2010), regularidad (Pase 2023),
  pasos (Ding 2025), zonas 1-3 (Lee 2022), zonas 4-5 (Ahmadi 2022), fuerza (Momma 2022), VO₂ (Lang 2024), FC reposo (Zhang 2016).
  Aeróbico cuenta una vez (mejor de pasos / zonas 1-3 / zonas 4-5). Ventana 90 días, «último mes» 30 días, se calcula a fecha
  del lunes (`AppModel.weekStart`). Ritmo = 1 + 12·(edad30 − edad90). Gus no quiere márgenes de error a la vista.
- Sueño: `SleepScoreHeader` (anillo, horas acostarse/levantarse, `SleepFactors`). En vivo: `LiveHeroMonitor`, `VitalsGrid` con ficha
  y rangos verde/naranja/rojo, `ChartScrub` para recorrer gráficas con el dedo. Laboratorio oculto (7 toques en Versión).

## Estado (2026-11-01, fórmulas con estudios)

- `RRCorrection` (Lipponen & Tarvainen 2019, constantes de NeuroKit2: α 5,2, ventana 91, mediana 11, c1 0,13, c2 0,17)
  dentro de `HRV.clean`; solo corre si hay un salto >15 % entre latidos (rendimiento). Corrige, no borra.
- VO₂ máx por carreras (`Fitness.vo2maxFromRun`: ACSM 0,2·v+3,5 y %FCR = %VO₂R, Swain 1997); mediana de 90 días con ≥3
  carreras sustituye a Uth en `HistoryMerge.days(workouts:)`.
- `HRVTrend`: media de 7 noches de ln RMSSD vs 60 días ± 0,5 DE (Plews/Buchheit, AIS). Tarjeta en Recuperación.
- Respiración solo en sueño no-REM (Natarajan 2021). Calorías: Keytel 2005 con VO₂ máx. `derivedVersion` 7. 205 tests.


## Estado (2026-11-02, En vivo, constantes e Inteligencia por niveles)

- En vivo: sin actividad solo `StartActivityCard` (+ Registrar actividad → `StartActivitySheet`: en directo o a mano); la gráfica,
  los minis y el entreno solo aparecen con `liveWorkout` activo.
- Constantes (`App/Views/Vitals/VitalsViews.swift`): `AppModel.vitalReadings()` / `vitalsSummary` (Bien/Regular/Mal = peor nivel).
  Inicio: `HomeVitalsStatusTile` + `HomeStressStatusTile` bajo los diales. Drill-down: `VitalsCard` → `VitalsView` → `VitalDetailView` → tendencia.
- Estrés: `StressLine` es una sola línea unida (monotone) con relleno; el color va por niveles con `StressLine.stops`.
- Inteligencia (`IntelligenceSummary.swift`): `IntelHeroCard` (un veredicto) + 3 áreas + Herramientas; cada una abre
  `IntelTodayView` / `IntelSectionView(title:)` / `IntelMoreView`, y sus métricas `MetricDetailView`.
- CI: `[paginas:a,b,c]` en el commit captura solo esas pantallas (`SHOTS_ONLY`). Si GitHub no da Mac, `gh run rerun <id> --failed`.

## Estado (2026-11-02, fórmulas contrastadas con lo publicado y con la exportación de Gus)

- Referencia de cómo calcula cada métrica la pulsera original (patentes, API, white paper de Healthspan, estudios):
  `docs/CALCULOS-REFERENCIA-2026-11-02.md`. Casi todas las constantes son privadas.
- Contrastado con la exportación real de Gus (148 días) y 3 noches con la pulsera en Pulso (copia en Descargas, no en el
  repo). Replay: `PULSO_REAL_DB=/ruta/copia.sqlite swift test --filter RealDataReplayTests` (líneas `NIGHT`).
- Necesidad de sueño = base + `1,7/(1+e^((17−esfuerzo)/3,5))` h (patente; en la exportación peso 0,99, error 2 min) + deuda − siestas.
- Deuda = 0,703·deuda anterior + 0,289·déficit (o 0,896·superávit) de la noche anterior, tope 180 min (ajustada; es el
  «extra por deuda» de la necesidad, como en la exportación). La base sale del perfil (revisarla contra la exportación).
- Recuperación = 100·σ(−2,166 + 0,504·zVFC − 0,049·zFCreposo + 4,096·suficiencia) (ajustada; 7,9 puntos de error fuera de
  muestra vs ~11). Respiración, temperatura y SpO₂ fuera del %. Línea base 28 noches ponderada (vida media 14).
- Calificación del sueño = −28,5 + 0,864·suficiencia + 0,357·constancia + 0,197·eficiencia (ajustada; 5,8 vs 9,2).
- Constancia: últimas 24 h vs cada uno de los 4 días anteriores, escala SRI (error 7 puntos, r 0,92).
- VFC: ventanas de 5 min cada 30 s, sin vigilia, más peso a profundo y final de noche (error ~2,5 ms en 3 noches vs ~9).
- Fases: `SleepStager.wakeBias −2,5 / deepBias 0,75 / remBias 0,3` (ajustado a las 3 noches: error total 507 → 189 min).
  Respiración: banda 0,2–0,5 Hz (error ≤ 0,6 rpm; antes ~4 rpm por debajo). Zonas: Z1 40–60 % FCR, FC reposo 14 días.
- Un día de pulsera sin noche toma la noche importada para la deuda y las líneas base (`DayEngine.withImportedNight`).
- Edad Pulso con el método del white paper (10·ln(HR), 6 meses, umbrales por edad/sexo, ajuste 0,85 → −1,6 años en los
  miembros medianos). Comportamientos: 90 días, impacto ajustado por sueño y esfuerzo previo. Planificador 100/85/75 %.
- Esfuerzo, estrés y calorías sin cambios (constantes no publicadas). `derivedVersion` 8.
- Ojo: las 3 noches son pocas; recalibrar `wakeBias`/`deepBias`/`remBias` y la banda con más noches de las dos pulseras.

## Estado (2026-11-04, fases de sueño contrastadas con 5 noches)

- Pulso contaba de más despierto (3-nov: 60 min vs 16) y profundo (4-nov: 158 vs 98). Contrastado con 5 noches con las dos
  pulseras en la misma muñeca (31-oct a 4-nov; error total en las 4 fases 425 → 353 min):
  - `absorbArousals`: un tramo despierto dentro de la noche pasa a ligero si el pulso no sube `wakeHRRise` 5 lpm sobre la
    mediana de los 31 min de alrededor, la muñeca no pasa de `wakeMotionFactor` 4 × umbral de quietud y la pulsera no lo
    marca despierto. Los bordes de la noche no se tocan.
  - `deepLatency` 20: nada de profundo en los primeros 20 min de sueño (se llega a N3 pasando por ligero).
  - `detrendMinutes` 30: pulso y ln RMSSD se leen contra la mediana de su hora (±30 min) antes del z-score; con la media de
    toda la noche, un pulso alto al acostarse convertía el resto en horas de profundo. `deepBias` 0,75 → 0,55 (dejando una
    noche fuera sale 0,55 las 5 veces; meseta 0,5-0,6 con 25-40 min).
  - Por noche (error antes → ahora): 31-oct 29 → 87, 1-nov 118 → 60, 2-nov 40 → 44, 3-nov 48 → 66, 4-nov 190 → 96.
- Simulación rápida: volcar por minuto las variables del `SleepStager` y repetir el decode en Python (reproduce Swift
  minuto a minuto). Los CSV de segundos de la app se convierten a SQLite para el replay (rr = uint16 LE).
- El bit «off» de la pulsera marca a menudo contacto flojo (piel a 34 °C, con pulso y R-R), no pulsera quitada. Tratarlo
  como puesta arregla la hora de dormirse automática (2-nov 01:24 vs 01:26; 4-nov empieza 01:06 vs 00:50) pero empeora
  profundo y VFC: pendiente, solo para la detección.
- Recalibrar con más noches (Gus manda copia + exportación cada semana). `derivedVersion` 9.

## Estado (2026-11-04, rama release-2026-11-04: Inicio, monitor de salud, Live)

- Inicio: diales grandes arriba que al desplazar se encogen en la fila fija (`HomeDialHeader`, preferencia `HomeScrollOffset`
  con `+=`), debajo `HomeHealthMonitorTile` | `HomeStressStatusTile` a medias y `TodayActivitiesCard` (sueño, siestas, entrenos,
  respiración; Agregar/Iniciar actividad). Agregar actividad rehecha (`AddActivitySheet` + `ActivityPickerView` con buscador y
  pestañas Todo/Esfuerzo/Recuperación/Sueño; ubicación de la pulsera en las notas).
- Monitor de salud (`HealthMonitorViews.swift`): página con pulso en vivo + baldosas por constante → `VitalPanel` → tendencias.
  SpO₂ con rangos clínicos (≥95 / 90–94 / <90). Informe de salud PDF 30/180 días (`HealthReport` en PulsoAnalytics, 4 páginas A4).
- Estrés por minuto también andando, dormido o entrenando: pulso «adicional» que el movimiento no explica (Myrtek 2004,
  Verkuil 2016) en `Stress.everyMinute`, `DaySummary.stressMinutes`, `derivedVersion` 10. Gráfica de las últimas 24 h.
  `StressSummary.split`: minutos de estrés alto en entreno (o 90 min después), sueño (60 min tras despertar / siestas) u otros.
- Live (antes «En vivo»): respiración guiada (`Breathwork`: alerta, suspiro fisiológico, coherencia, caja, 4-7-8) con la pulsera
  vibrando en cada fase, resultado con estrés/FC y registro como actividad (kv `breathwork.sessions`); alerta de estrés
  (`StressAlert`: 5 min quieto con estrés ≥ 2, 1 h de silencio, nunca en tu horario de sueño, CoreMotion para saber si andas);
  resumen a las 21:00 de dónde vino el estrés alto. Tests, sauna/baño de hielo y monitor en la misma pestaña.
- Pendiente acordado: siesta inteligente y detección de dormirse con 4-7-8, primero en silencio (solo registrar) y contrastar.
- CI: tests del núcleo en `-c release -Xswiftc -enable-testing --parallel` (en debug ya pasaban de 45 min y el job se cortaba
  a la hora). Capturas: `gh workflow run ios.yml --ref <rama> -f capturas=true -f pantallas="today live …"`. Releases solo desde main.
- VO₂ máx (2026-11-05): Uth (15,3 × FCmáx / FC reposo) con la FC de sueño daba 54-58 frente a 42-43 de la pulsera original en
  la misma muñeca. Ahora `Fitness.passiveVO2` = Jurca 2005 (sexo, edad, IMC, FC reposo, puntos de actividad desde minutos en
  zonas 2-5 de 4 semanas / zona 1 / pasos): con los datos de Gus 42,1-43,5. Las carreras (3+ en 90 días) siguen mandando.
  Estrés por minuto suavizado (mediana 5 min + media exponencial 0,25), gráfica de una línea con colores por nivel. `derivedVersion` 13.
