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
- Núcleo: 75 tests en verde con Swift 6.2 en Linux (WSL Ubuntu 24.04 en el PC de Gus:
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
