# Pulso

App de iPhone que se conecta **directamente** a una pulsera **WHOOP 5.0 / MG** por Bluetooth,
descarga sus datos y calcula todo en el propio iPhone. No usa la app ni la nube de WHOOP, no
tiene cuentas ni servidores, y nunca envía nada fuera del teléfono.

> Proyecto personal no afiliado a WHOOP, Inc. No es un dispositivo médico: todas las métricas
> son estimaciones de bienestar.

## Qué hace

| Pantalla | Contenido |
|---|---|
| **Hoy** | Anillos de Recuperación (0–100 %), Esfuerzo (0–21) y Sueño (%). Desglose del **porqué** de la recuperación: cuánto suma o resta cada factor. VFC, FC en reposo, respiración, SpO₂, temperatura de la piel, calorías, pasos, VO₂máx y edad cardio. Zonas cardiacas del día, entrenos detectados, estrés por horas y diario de hábitos. |
| **Sueño** | Hipnograma (despierto / ligero / profundo / REM), duración frente a necesidad, rendimiento, eficiencia, consistencia, deuda de 7 días, latencia y despertares. FC y VFC a lo largo de la noche. Siestas. Puedes corregir las horas a mano y todo se recalcula. |
| **Tendencias** | 7 / 30 / 90 / 365 días de recuperación, VFC, FC en reposo, esfuerzo, sueño, respiración, temperatura, estrés y VO₂máx. **Qué te afecta**: efecto real de cada hábito del diario en tu recuperación del día siguiente. |
| **En vivo** | Pulso en tiempo real con zona, VFC en vivo, registro de entrenos con esfuerzo y calorías al momento, respiración guiada con biofeedback y botón para hacer vibrar la pulsera. |
| **Más** | Estado de la pulsera (batería, firmware, serie), sincronización, perfil, despertador por vibración, Apple Salud, importación del histórico de WHOOP (CSV), exportación CSV de todo (incluido cada segundo), retención de datos y borrado. Metodología de cada cálculo. |

Además:

- **Tus datos son tuyos**: exporta en CSV los días, los entrenos y los datos por segundo (FC, R-R, gravedad, movimiento, temperatura, SpO₂, pasos).
- **Apple Salud**: FC por minuto, FC en reposo, VFC (SDNN), respiración, SpO₂, fases del sueño y energía de entrenos (sin duplicados).
- **Arranque en caliente**: importa `physiological_cycles.csv` de tu exportación de WHOOP y las líneas base (VFC, FC reposo, respiración, temperatura) quedan calibradas desde el primer día.

## Instalación (PC con Windows + iPhone)

La app la compila GitHub en sus Mac en la nube. Cada cambio en `main` genera `Pulso.ipa` en
*Releases → ultima*. Tú solo la instalas con **Sideloadly**.

### Una vez (unos 15 minutos)

1. **En el iPhone**: *Ajustes → Privacidad y seguridad → Modo de desarrollador* → actívalo. El iPhone se reinicia; al volver confirma «Activar».
2. **En el PC**: instala **iTunes** e **iCloud** descargados de la web de Apple, no los de Microsoft Store. Si ya tienes los de la Store, desinstálalos antes. Después instala [Sideloadly](https://sideloadly.io).
3. Descarga `Pulso.ipa` desde la pestaña **Releases** del repositorio.
4. Conecta el iPhone por cable, desbloquéalo y pulsa **Confiar** en este ordenador.
5. Abre Sideloadly y sigue estos pasos:
   1. Arrastra `Pulso.ipa`.
   2. Escribe tu Apple ID y pulsa **Start**.
   3. Te pedirá tu contraseña y el código de verificación que llega a tu iPhone. Esos datos solo los ves tú.
6. **En el iPhone**: *Ajustes → General → VPN y gestión de dispositivos* → toca tu Apple ID → **Confiar**.

Si prefieres no usar tu Apple ID principal en una herramienta de terceros, créate un Apple ID gratuito secundario solo para esto. Funciona igual.

### Renovación cada 7 días

Con un Apple ID gratuito la firma caduca a los 7 días; con la cuenta de desarrollador de pago, al año. Sideloadly lo renueva solo si activas **Automatic refresh**:

- Desde el PC: en el menú del icono de Sideloadly, o al instalar, en *Advanced options*.
- En el iPhone: Wi-Fi en la misma red que el PC.
- Si caduca: vuelve a instalarla. **Tus datos no se pierden**, mientras no borres la app.

### Alternativa con Mac

Abre `Pulso.xcodeproj` en Xcode 16 o posterior. En *Signing & Capabilities* elige tu Apple ID como *Team*, conecta el iPhone y pulsa ▶︎.

## Emparejar la WHOOP 5.0

La pulsera solo admite **un** emparejamiento a la vez:

1. En la app de WHOOP, desvincula la pulsera (o desinstala la app).
2. iPhone → *Ajustes → Bluetooth* → (i) junto a la WHOOP → *Omitir dispositivo*.
3. Toca la pulsera varias veces seguidas hasta que los LED parpadeen en **azul** (modo emparejamiento).
4. En Pulso: *Más → Pulsera → Buscar pulsera* y acepta la solicitud de emparejamiento de iOS.

Al conectar, Pulso:

1. Pone en hora la pulsera. Sin reloj, la pulsera no guarda datos.
2. Descarga el historial que tenga guardado (hasta unos 14 días).
3. Solo después de guardar cada bloque confirma a la pulsera que puede liberarlo.

Nunca envía comandos de borrado, firmware, reinicio ni cambios de configuración persistentes: esos códigos están bloqueados en el propio código.

Lo que conviene saber sobre la sincronización:

- **Velocidad**: unos 200–250 segundos de datos por segundo real. Un día completo tarda unos 6 minutos.
- **Primera noche**: da tu primer sueño y tu esfuerzo.
- **Calibración**: la recuperación aparece a partir de la 5.ª noche, con 4 de calibración (igual que WHOOP). Si importas tu CSV de WHOOP, aparece desde la primera.
- **Segundo plano**: deja la app en segundo plano. iOS reconecta solo cuando la pulsera está cerca, y Pulso sincroniza al abrirla, con eventos de la pulsera y en las actualizaciones en segundo plano.

## Cómo funciona

```
Pulso/
├── App/                       App iOS (SwiftUI + CoreBluetooth + HealthKit + Swift Charts)
│   ├── BLE/StrapManager.swift     Conexión, emparejamiento, reloj, descarga con ACK, pulso en vivo
│   ├── Model/AppModel.swift       Estado de la app, análisis en segundo plano, import/export
│   ├── Health/HealthExporter.swift
│   ├── Design/Theme.swift         Colores, anillos y componentes
│   └── Views/                     Hoy, Sueño, Tendencias, En vivo, Más
└── Packages/PulsoKit/         Núcleo en Swift puro (compila y se prueba también en Linux)
    ├── WhoopProtocol/             Tramas, CRC8/16/32, comandos, decodificadores, sesión de descarga
    ├── PulsoStore/                SQLite local (datos por segundo + resúmenes)
    └── PulsoAnalytics/            Sueño, fases, VFC, respiración, recuperación, esfuerzo, estrés…
```

Tests del núcleo: `cd Packages/PulsoKit && swift test`. Validan tres cosas:

- **Protocolo**: tramas **reales** capturadas de una WHOOP 5.0 (saludo, registro v18, fin de bloque, checksums).
- **Almacenamiento**: base de datos local.
- **Pipeline completo**: una semana sintética fisiológicamente realista. Comprueba la detección del sueño, las fases, la VFC, la respiración, los entrenos, el esfuerzo y que una mala noche baja la recuperación.

Todos los cálculos se explican en la app (*Más → Cómo se calcula cada métrica*) y en [`docs/PROTOCOLO.md`](docs/PROTOCOLO.md).

## Estado y límites

**Probado**

- Decodificación contra tramas reales publicadas.
- Algoritmos contra datos sintéticos.
- Compilación del núcleo y verificación de tipos de toda la app.

**Pendiente de validar con tu pulsera**

- El flujo Bluetooth completo. Sigue la secuencia que la comunidad ha verificado en hardware real. Si algo falla, *Más → Registro de conexión* muestra cada paso.

**Experimental**

- El despertador por vibración de la pulsera en 5.0. Por eso el iPhone también suena como respaldo.

**Estimaciones**

- Pasos.
- Fases del sueño: la precisión típica de cualquier wearable de muñeca ronda el 65–75 % frente a un laboratorio.
- VO₂máx.

**No disponible**

- ECG (solo MG), tensión arterial y los modelos propietarios de WHOOP.
- WHOOP 4.0: tiene otro protocolo y no está soportada.

## Créditos

El protocolo Bluetooth de la WHOOP 5.0 lo han documentado por ingeniería inversa proyectos open
source como `whoop-rs`, `noop`, `OpenStrap`, `goose` y el análisis de Alec Jude Wilson. El código de
Pulso es original, pero se apoya en sus hallazgos. Uso personal.
