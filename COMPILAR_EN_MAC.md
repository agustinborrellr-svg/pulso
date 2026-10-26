# Instalar Pulso en el iPhone de Gus desde un Mac

Unos 15 minutos. No hace falta cuenta de desarrollador de pago: vale el Apple ID gratuito de Gus.

## Qué necesitas

- Un Mac con **Xcode 26** (App Store, gratis). Se ha probado con Xcode 26.3; con Xcode 16 también debería ir.
- El iPhone de Gus con iOS 17 o posterior y su cable.
- Que Gus esté al lado para poner su Apple ID y el código de verificación.

## Pasos

1. Descomprime `Pulso-Xcode.zip` y haz doble clic en **`Pulso.xcodeproj`**.
   La primera vez Xcode resuelve el paquete local `PulsoKit` (unos segundos, no descarga nada de internet).
2. *Xcode → Settings → Accounts → +* → **Apple ID** → Gus inicia sesión con su Apple ID.
3. En el navegador de la izquierda pulsa el proyecto **Pulso** (icono azul arriba del todo).
   Para **cada uno de los dos targets**, `Pulso` y `PulsoWidgets`:
   *Signing & Capabilities* → marca *Automatically manage signing* → **Team: el de Gus, el que pone «(Personal Team)»**.
4. Si Xcode dice que el bundle identifier no está disponible, cámbialo en los dos targets
   (por ejemplo `es.gusborrell.pulso` → `es.gusborrell.pulso2` y `es.gusborrell.pulso.widgets` →
   `es.gusborrell.pulso2.widgets`). El del widget debe empezar igual que el de la app.
5. Si Xcode se queja de un *App Group* o de una *capability*: en ese target, en *Signing & Capabilities*,
   pulsa la papelera junto a **App Groups**. La app funciona igual; solo los widgets dejan de ver los datos.
   No quites **HealthKit** ni **Background Modes**.
6. Conecta el iPhone, desbloquéalo y pulsa «Confiar». En el iPhone: *Ajustes → Privacidad y seguridad →
   Modo de desarrollador* → activar (se reinicia).
7. Arriba en Xcode elige el iPhone de Gus como destino y pulsa **▶ Run** (⌘R).
8. La primera vez el iPhone dirá «desarrollador no fiable»: *Ajustes → General → VPN y gestión de
   dispositivos* → el Apple ID de Gus → **Confiar**. Vuelve a pulsar ▶ en Xcode.

## Después

- Con Apple ID gratuito la app **caduca a los 7 días**. Para renovarla basta con volver a conectar el iPhone a
  un Mac con este proyecto y pulsar ▶ (los datos de la app se conservan).
- Si Gus tiene una cuenta de desarrollador de pago (99 €/año), dura un año.
- No toques el código: compila tal cual (está comprobado en GitHub Actions con Xcode 26.3).
  Si falla, haz una captura del error del panel *Issue navigator* (⌘5) y mándasela a Gus.
