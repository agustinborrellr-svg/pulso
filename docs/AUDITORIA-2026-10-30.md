# Auditoría integral — 30 oct 2026

Base: commit `565e5e4`. Núcleo: 59 tests XCTest en verde (1 omitido). Auditoría leyendo código; nada
validado aún con la pulsera ni con los datos reales de Gus. Etiquetas: **[ERROR]** fallo, **[FICTICIO]**
dato presentado como real sin serlo, **[INERTE]** control que no hace nada, **[RIESGO]**, **[OK]**.

## 1. Datos y pulsera

| Hallazgo | Estado | Dónde |
|---|---|---|
| Se confirma (ACK) a la pulsera un bloque con registros no decodificados → la pulsera los borra: **pérdida de datos** | [ERROR] alta | `Offload.swift:33`, `StrapManager.swift:627,649` |
| Una sincronización fallida actualiza `lastSync` y apaga el aviso «sin sincronizar» | [ERROR] | `StrapManager.swift:664` |
| `samples` no guarda la fuente: real, en vivo y demo se mezclan; quitar la demo borra datos reales | [RIESGO] | `Database.swift:53`, `AppModel+Demo.swift:49` |
| SpO₂ sale de un byte sin confirmar y entra en la recuperación | [FICTICIO] | `Records.swift:74`, `DayEngine.swift:332` |
| Los eventos de la pulsera (puesta/quitada, doble toque) no se guardan; doble toque = evento 14 sin verificar | [RIESGO] | `AppModel.swift:651` |
| Búsqueda: 45 s fijos sin estado «terminado»; «Escanear» en vivo: 60 s fijos | [MEJORA] | `StrapManager.swift:415`, `LiveToolsViews.swift:150` |
| Restaurar copia borra la base antes de mover la nueva e ignora errores; copia de seguridad previa en el hilo principal | [RIESGO] | `AppModel+Integrations.swift:180`, `AppModel+Backups.swift:32` |

Qué da la pulsera: FC por segundo, hasta 4 R-R por segundo, gravedad x/y/z + aceleración dinámica (no
acelerómetro bruto), contador de pasos acumulado, clase de actividad, estado de sueño propio, temperatura
cutánea, batería. Todo lo demás (VFC, respiración, fases, recuperación, esfuerzo, estrés, calorías,
VO₂máx) lo calcula Pulso.

## 2. Día fisiológico, sueño y siestas

- [OK] La regla de día es correcta: la noche del 29→30 que acaba a las 09:00 pertenece al 30 (`DayEngine.swift:123`).
- [ERROR] alta: mientras la noche no está descargada/analizada, Inicio **muestra el día anterior entero** como si fuera hoy (`AppModel.swift:173`). Es la causa de «se ven datos del día anterior».
- [ERROR] alta: detección de siestas demasiado sensible (75 % quieto + FC ≤ suelo+12 → «siesta»; sin postura, VFC ni fases) (`SleepDetector.swift:46`).
- [ERROR] no existe «no dormí»: borrar una siesta automática se deshace en el siguiente recálculo; editar una siesta crea un duplicado que se cuenta dos veces (`DayEngine.swift:174,188`).
- [ERROR] la pantalla que permite editar/borrar/añadir siestas (`SleepView.swift`) no está enlazada desde ningún sitio.
- [FICTICIO] «Tiempo en cama» = bloque de sueño detectado; latencia ≈ 0 y eficiencia inflada.
- [RIESGO] deuda de sueño contada dos veces; dos definiciones distintas de deuda.

## 3. Métricas

- **Estrés**: se mide contra tus mejores momentos (FC percentil 25 / VFC percentil 75) → casi siempre por encima de cero; las horas después de entrenar cuentan como estrés; las horas tras medianoche se dibujan a la izquierda. No es una suma acumulada, pero lo parece.
- **Esfuerzo** [OK]: TRIMP por minuto según % de reserva, se actualiza durante el día.
- **Pasos**: contador acumulado u16, se pierden pasos en huecos o reinicios (saltos ≥512 descartados); ventana despertar→ahora, no día natural. la diferencia con WHOOP es compatible con esto, sin demostrar.
- **FC máxima**: ancla = máximo de 180 días sin filtro de valores atípicos; un minuto espurio rebaja esfuerzo/zonas e infla VO₂máx 6 meses.
- **VO₂máx** [FICTICIO]: Uth con FC de sueño (más baja que la FC en reposo despierto) → sale alto; en el panel aparece sin «estimado».
- **Edad Pulso** más joven que la de WHOOP: los dos pesos mayores (VO₂máx 1,5 y FCR 0,9) usan valores halagadores; hoy parcial cuenta como día completo; días importados sin zonas cuentan como cero.

## 4. Análisis

- **Coste cardíaco 2/5**: sólo cuenta días con pulso por minuto de Pulso; los ~140 días importados de WHOOP no lo traen. El «2» son dos días medidos por Pulso. No es un error de conteo; el texto engaña.
- **21 noches** (coste de despertar, sensibilidad horaria): exige despertares, que el CSV de WHOOP no trae → sólo cuentan noches de Pulso. «Falta: 21 noches» muestra el requisito total, no lo que falta.
- **Hábitos** («Desayuno −19»): decenas de pruebas al 90 % sin corrección (≈1 de cada 10 «claros» es azar); se colorea aunque el intervalo cruce 0; no muestra n.
- **Coherencia 64/100**: percentil de lo raro que es la noche frente a las 28 anteriores; «alta» sólo significa ≥28 noches. «Anoche» puede ser otra noche sin avisar.
- **Explorador**: «día siguiente» por posición en la lista (empareja días no consecutivos si hay huecos); el emparejamiento por defecto usa la noche equivocada.
- **Techo de carga**: descarta justo los días que no se recuperan (sobrecarga).

## 5. Herramientas, ECG e interfaz

- [INERTE] Ortostático, Recuperación FC, FC máx, Escanear, Empezar entreno: deshabilitados salvo estado `.ready`; la 5.0 suele rechazar el emparejamiento pero manda pulso estándar → se ve el pulso y los botones no hacen nada; el estilo del botón no muestra el estado deshabilitado (`PulsoUI.swift:269`).
- [ERROR] Poincaré sólo se recalcula al cambiar el pulso y nunca explica que faltan R-R.
- [FICTICIO] ECG simulado: titular «Ritmo sinusal», usa tu pulso real, el PDF «para el médico» no dice SIMULADO en el título ni en el nombre del archivo. La pantalla gris/bloqueada = resultado sin scroll que se recorta.
- [FICTICIO] Widgets sin App Group muestran siempre 72 / 9,8 / 68.
- [FICTICIO] El corazón sigue latiendo con el último valor tras desconectar; no se indica antigüedad.
- Diseño: dos juegos de componentes paralelos (`Card` vs `PCard`), 112 tamaños de letra fijos (Dynamic Type ignorado), 1 etiqueta de accesibilidad en toda la app. Sin emojis como iconos [OK].

## Plan por fases

**Fase 1 — integridad (en curso)**
1. No confirmar bloques con registros sin decodificar; `lastSync` sólo tras sincronización correcta.
2. Inicio: estado «analizando tu noche» en vez de mostrar el día anterior.
3. Siestas: decisión «no dormí» persistente, sin duplicados con manuales, detección más estricta, pantalla de edición enlazada.
4. Botones de pruebas: estado deshabilitado visible + motivo; habilitar con pulso en vivo real.
5. ECG simulado marcado en pantalla, historial y PDF; corazón parado sin dato fresco.
6. Análisis: textos «Faltan N», sensibilidad horaria con historial importado, coste cardíaco explicado.

**Fase 2 — algoritmos**: estrés (referencia mediana por hora, excluir post-entreno), ancla de FC máx robusta, VO₂máx/Edad Pulso con FCR despierto y «estimado», SpO₂ como experimental, hábitos con n y corrección múltiple, explorador por fecha, deuda única.

**Fase 3 — producto y diseño**: sistema de diseño único, Dynamic Type y accesibilidad, monitor fisiológico, tendencias con selector, calendario, laboratorio explicado, animación de conexión, imagen del dispositivo.

**Pendiente de validación física** (necesita la pulsera o una copia de seguridad de Gus): conteo real de noches/días, pasos, byte de SpO₂, evento de doble toque.

## Hecho (30 oct, sesión 1)

| Cambio | Archivos | Pruebas |
|---|---|---|
| Registros del historial sin decodificar se guardan (tabla `undecoded_records`, migración 2) **antes** del ACK; `lastSync` sólo si la descarga termina bien | `Offload.swift`, `Database.swift`, `StrapManager.swift`, `AppModel.swift` | `testUndecodedHistoryRecordsTravelWithTheirChunk` |
| Tarjeta «Tu noche aún no está descargada / No encuentro tu noche» en Inicio, con sincronizar o añadir sueño, en vez de mostrar el día anterior como hoy | `NightStatus.swift`, `HomeView`, `SleepQuestionCard.swift` | `NightStatusTests` (5) |
| Siestas: detección diurna más estricta (flag de sueño de la pulsera, o ≥30 min con FC cerca del suelo nocturno); «No dormí» persistente; borrar una automática no vuelve; editar no duplica; siestas manuales analizadas (antes contaban 0 min); añadir/ajustar/descartar desde Sueño | `SleepDetector`, `DayEngine`, `Models`, `AppModel(+Naps)`, `SleepDetailView`, `SleepView` | 4 tests nuevos en `SleepConfidenceNapTests` |
| Botones de pruebas en vivo: se activan con pulso en vivo real (aunque la pulsera rechace el emparejamiento), muestran el motivo si no, y el estilo enseña el estado deshabilitado. Ortostático dice cuántos latidos faltaron | `PulsoUI.swift`, `LiveToolsViews.swift`, `AppModel.swift` | compila; pendiente en pulsera |
| Corazón en vivo: se para y avisa «sin señal: hace X s»; el pulso se borra al desconectar | `LiveView.swift`, `AppModel.swift` | pendiente en pulsera |
| ECG simulado → «Demostración», aparte, sin tu pulso, banner amarillo, sin PDF; el PDF de una simulación titula «SIMULACIÓN - NO ES UN ECG REAL»; el resultado hace scroll | `ECGView`, `AppModel+ECG`, `ECGReport` | test de PDF actualizado |
| Análisis: «Faltan N · necesita…»; sensibilidad al horario usa también las noches importadas (con término por fuente); coste de despertar y coste cardíaco dicen que necesitan noches/días medidos por Pulso | `Rhythms.swift`, `AnalysisExtras.swift` | `testImportedNightsCountForTimingButNotForAwakenings` |
| Estrés: referencia = mediana de tus momentos quietos (no el cuartil más tranquilo), excluye 90 min tras entrenar; gráfica desde la hora de despertar, sin unir huecos, color según el nivel real | `Recovery.swift`, `DayEngine`, `HomeView`, `StrainDetailView`, `HealthView` | `StressTests` |
| FC máx: ancla = segundo pico diario más alto (un minuto espurio ya no fija zonas/esfuerzo/VO₂ 6 meses) | `Activity.swift`, `DayEngine`, `HistoryMerge`, `AppModel` | `MaxHRAnchorTests` |
| SpO₂ fuera de la recuperación y marcado «experimental»; VO₂ máx «estimado» | `DayEngine`, `TrendMetric`, `PulsoAge` | — |
| Edad Pulso: sin el día en curso; días importados sin zonas no cuentan como cero | `PulsoAge.swift` | suite existente |
| Hábitos: n por hábito, los no claros en gris y «no claro», aviso de comparaciones múltiples | `AnalysisExtras.swift` | — |
| Explorador: «día siguiente» por fecha (no por posición); por defecto mismo día; frase de asociación | `AnalysisTools.swift`, `AnalysisExtras.swift` | `RelationByDateTests` |
| Laboratorio explicado; repeticiones 1–8 y efectos ≤251 (límites reales); contador de registros sin decodificar | `LabView.swift` | — |
| Búsqueda de pulsera: estado «terminada» con «Buscar de nuevo» | `DeviceView.swift` | — |
| `derivedVersion` 3 → 4: al abrir, todo se recalcula con los algoritmos nuevos | `DayEngine.swift` | — |

### Pendiente
Ver `INFORME-2026-10-30.md` (secciones G, H y J): todo el plan de fases 1–3 está hecho; lo que queda es la validación
con la pulsera física y con una copia de seguridad real.
