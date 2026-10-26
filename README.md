# Pulso

App de iPhone que se conecta **directamente** a una pulsera **WHOOP 5.0 / MG** por Bluetooth,
descarga sus datos y calcula todo en el propio iPhone. No usa la app ni la nube de WHOOP, no
tiene cuentas ni servidores, y nunca envía nada fuera del teléfono.

> Proyecto personal no afiliado a WHOOP, Inc. No es un dispositivo médico: todas las métricas
> son estimaciones de bienestar.

## Qué hace

| Pantalla | Contenido |
|---|---|
| **Hoy** | Anillos de Recuperación (0–100 %), Esfuerzo (0–21) y Sueño (%). **Plan del día**: esfuerzo objetivo, aviso de **posible enfermedad**, estado de la carga de entrenamiento y **a qué hora acostarte**. Desglose del **porqué** de la recuperación. VFC, FC en reposo, respiración, SpO₂, temperatura, calorías, pasos, VO₂máx y edad cardio. Zonas, entrenos, estrés por horas, marcas de doble toque y diario de hábitos. |
| **Sueño** | Hipnograma (despierto / ligero / profundo / REM), duración frente a necesidad, rendimiento, eficiencia, consistencia, deuda de 7 días, latencia y despertares. FC y VFC a lo largo de la noche. Siestas. Puedes corregir las horas a mano y todo se recalcula. |
| **Tendencias** | 7 / 30 / 90 / 365 días de recuperación, VFC, FC en reposo, esfuerzo, **carga aguda/crónica**, sueño, respiración, temperatura, estrés y VO₂máx. Resumen semanal, ciclo menstrual (opcional) y **qué te afecta**. |
| **En vivo** | Pulso en tiempo real con zona y VFC, entrenos con esfuerzo y calorías al momento, **planes de intervalos** (4×4, 30/30, Tabata, pirámide, zona 2, tempo) con vibración y voz, vueltas, respiración guiada y Live Activity en la Dynamic Island. |
| **Más** | Pulsera, perfil, **despertador** (varias alarmas, inteligente, por objetivo de sueño, posponer con doble toque, respaldo con alarma del iPhone), **avisos**, **conexiones** (Apple Salud, Strava, pulsómetro para otras apps), **electrocardiograma**, doble toque configurable, copia de seguridad, exportación CSV, laboratorio y metodología. |

Además:

- **Despertador**: tantas alarmas como quieras, por días. Tres modos: hora fija, **inteligente** (vibra en sueño ligero dentro de una ventana) y **cuando hayas dormido lo necesario**. Vibración suave, normal, fuerte o progresiva. Doble toque para posponer o apagar. Si la pulsera no te despierta suena el iPhone (alarma del sistema con AlarmKit en iOS 26, avisos repetidos en versiones anteriores) y la propia pulsera tiene su alarma de respaldo.
- **Avisos**: informe al despertar, hora de acostarse, última cafeína, posible enfermedad, tendencias de VFC/FC/deuda, batería baja, pulsera fuera de la muñeca, sin sincronizar, objetivo de esfuerzo, te estás pasando, mucho rato quieto, estrés alto y resumen semanal. Cada uno se activa por separado, puede vibrar la pulsera y respeta las horas de silencio.
- **Apple Salud**: envía FC, FC en reposo, VFC, respiración, SpO₂, fases de sueño y **entrenos completos con su pulso**. Importa los entrenos de **otras apps** (Garmin, Strava, Nike, Peloton, gimnasio…) y los **ECG del Apple Watch**.
- **Strava**: sube cada entreno como archivo FIT (pulso segundo a segundo, esfuerzo, calorías) e importa tus actividades, combinándolas con los datos de la pulsera sin duplicar.
- **Pulsómetro para otras apps**: el iPhone emite tu pulso como un pulsómetro Bluetooth estándar («Pulso HR») para Zwift, Peloton, máquinas de gimnasio o ciclocomputadores.
- **Archivos**: exporta cada entreno en FIT o TCX (Garmin Connect, TrainingPeaks, Intervals.icu…).
- **Doble toque** en la pulsera: guardar una marca, empezar/terminar entreno, marcar vuelta o respiración guiada solo con vibraciones.
- **Siri y Atajos**: «¿Cómo está mi recuperación en Pulso?», empezar/terminar entreno, respirar, sincronizar.
- **Widgets** de pantalla de inicio y de bloqueo con recuperación, esfuerzo y sueño.
- **ECG preparado para la WHOOP MG**: análisis del ritmo, trazado en papel milimetrado y PDF para el médico. Funciona ya con ECG del Apple Watch y con un simulador; para la MG falta su protocolo (ver [`docs/ECG.md`](docs/ECG.md)).
- **Tus datos son tuyos**: exporta en CSV los días, los entrenos y los datos por segundo, o haz una **copia de seguridad** completa y restáurala.
- **Arranque en caliente**: importa `physiological_cycles.csv` de tu exportación de WHOOP y las líneas base quedan calibradas desde el primer día.

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

## Conectar Strava (una vez)

Pulso no tiene servidor, así que usa tu propia «app» de Strava (gratis, 5 minutos):

1. Entra en [strava.com/settings/api](https://www.strava.com/settings/api) y crea una aplicación: nombre «Pulso», web `http://localhost`, **Authorization Callback Domain** `localhost`.
2. En Pulso: *Más → Conexiones → Strava → Configurar* y pega el **Client ID** y el **Client Secret** (se guardan en el llavero del iPhone).
3. Pulsa **Conectar con Strava** y acepta.

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
│   ├── BLE/                       StrapManager (pulsera) y HRBroadcaster (pulsómetro estándar)
│   ├── Model/                     AppModel + extensiones: alarmas, avisos, integraciones, entrenos, ECG
│   ├── Services/                  Notificaciones, alarma del iPhone (AlarmKit), Strava, llavero, voz
│   ├── Health/                    Apple Salud (exportar, entrenos, importar entrenos y ECG)
│   ├── Intents/                   Siri y Atajos
│   ├── Design/Theme.swift         Colores, anillos y componentes
│   └── Views/                     Hoy, Sueño, Tendencias, En vivo, Más, Despertador, Avisos, Conexiones, ECG, Laboratorio
├── Widgets/                   Widgets y Live Activity del entreno
├── Shared/                    Código común a la app y los widgets
└── Packages/PulsoKit/         Núcleo en Swift puro (compila y se prueba también en Linux)
    ├── WhoopProtocol/             Tramas, CRC, comandos, decodificadores, descarga, grabadora de tramas
    ├── PulsoStore/                SQLite local (datos por segundo, resúmenes, ECG, copias)
    ├── PulsoAnalytics/            Sueño, VFC, recuperación, esfuerzo, estrés, carga, enfermedad, ciclo…
    ├── PulsoFeatures/             Alarmas, sesión de despertar, vibraciones, avisos, intervalos, gestos
    ├── PulsoIntegrations/         Strava, FIT, TCX, catálogo de deportes, pulsómetro 0x2A37
    └── PulsoECG/                  Análisis del ECG, simulador, PDF y decodificador de la MG
```

Tests del núcleo (91): `cd Packages/PulsoKit && swift test`. Validan:

- **Protocolo**: tramas **reales** capturadas de una WHOOP 5.0 (saludo, registro v18, fin de bloque, checksums).
- **Almacenamiento**: base de datos, ECG, copias de seguridad y compatibilidad con datos de versiones anteriores.
- **Pipeline completo**: una semana sintética fisiológicamente realista (sueño, fases, VFC, respiración, entrenos, esfuerzo, recuperación).
- **Alarmas**: planificación por días, ventana inteligente, sueño ligero frente a profundo, posponer, apagar y respaldo del iPhone.
- **Avisos**: cada regla, sin repetir, horas de silencio.
- **Strava y archivos**: OAuth, renovación del token, subida con espera, duplicados, límites; cabecera y CRC del FIT, y TCX como XML válido (la validación con un decodificador externo se hizo a mano, no está en CI).
- **ECG**: ritmo sinusal, bradicardia, taquicardia, fibrilación auricular simulada, arritmia respiratoria (no debe salir irregular), ruido; PDF válido.

Todos los cálculos se explican en la app (*Más → Cómo se calcula cada métrica*) y en [`docs/PROTOCOLO.md`](docs/PROTOCOLO.md).

## Estado y límites

**Probado**

- Decodificación contra tramas reales publicadas.
- Algoritmos contra datos sintéticos.
- Compilación del núcleo y verificación de tipos de toda la app.

**Pendiente de validar con tu pulsera**

- El flujo Bluetooth completo. Sigue la secuencia que la comunidad ha verificado en hardware real. Si algo falla, *Más → Registro de conexión* muestra cada paso.
- La alarma inteligente durante una noche real (la lógica está probada con datos sintéticos).
- Los patrones de vibración alternativos (el Laboratorio sirve para probarlos).

**Experimental**

- El despertador por vibración de la pulsera en 5.0. Por eso el iPhone también suena como respaldo.

**Estimaciones**

- Pasos.
- Fases del sueño: la precisión típica de cualquier wearable de muñeca ronda el 65–75 % frente a un laboratorio, y el modelo fuerza proporciones plausibles de profundo y REM.
- VO₂máx y edad cardio.
- SpO₂ y «fuera de la muñeca»: salen de bytes del registro cuya codificación la comunidad aún no ha fijado.
- El ECG sólo está validado contra su simulador, no contra registros reales.

**No disponible**

- ECG de la MG hasta que se conozca su protocolo (todo lo demás está hecho), tensión arterial y los modelos propietarios de WHOOP.
- Vibrar con las notificaciones de otras apps (WhatsApp, llamadas…): iOS no lo permite a apps de terceros.
- WHOOP 4.0: tiene otro protocolo y no está soportada.
- Widgets y Live Activity con un Apple ID gratuito (Sideloadly): necesitan App Groups, que sólo da la cuenta de desarrollador de pago.
- Que el pulsómetro Bluetooth lo vean equipos no Apple con Pulso en segundo plano.

Revisión de código y lista de pendientes: [`docs/REVISION-2026-10-26.md`](docs/REVISION-2026-10-26.md).

## Créditos

El protocolo Bluetooth de la WHOOP 5.0 lo han documentado por ingeniería inversa proyectos open
source como `whoop-rs`, `noop`, `OpenStrap`, `goose` y el análisis de Alec Jude Wilson. El código de
Pulso es original, pero se apoya en sus hallazgos. Uso personal.
