# Protocolo Bluetooth de la WHOOP 5.0 / MG (resumen técnico)

Esta es la referencia que implementa `Packages/PulsoKit/Sources/WhoopProtocol`. Los tests usan
tramas reales capturadas de una WHOOP 5.0.

## Servicios GATT

| UUID | Uso |
|---|---|
| `fd4b0001-cce1-4033-93ce-002d5875f58a` | Servicio propietario |
| `fd4b0002-…` | Escritura de comandos (siempre **con respuesta**) |
| `fd4b0003-…` | Notify: respuestas a comandos |
| `fd4b0004-…` | Notify: eventos |
| `fd4b0005-…` | Notify: datos (histórico, tiempo real) |
| `fd4b0007-…` | Notify: logs del firmware |
| `180D/2A37`, `180F/2A19`, `180A` | FC, batería e información estándar |

Los canales `fd4b0003–0007` rechazan la suscripción hasta que el enlace está cifrado.

## Emparejamiento

1. Conectar y descubrir servicios.
2. Escribir **con respuesta** en `fd4b0002` el saludo fijo
   `AA 01 08 00 00 01 E6 71 23 01 91 01 36 3E 5C 8D` (GET_HELLO, seq 1, cuerpo `01`).
   Esa escritura confirmada hace que iOS negocie el emparejamiento *just works*.
3. Si responde *Insufficient Authentication/Encryption*, la pulsera sigue vinculada a otro
   teléfono o app. Hay que desvincularla y ponerla en modo emparejamiento (LED azul).
4. Con la escritura confirmada, suscribirse a `fd4b0003/4/5/7`.

## Trama

```
AA 01 | len u16 LE | 00 01 | CRC16-Modbus(bytes 0..5) LE | inner … | CRC32(inner) LE
inner = [tipo][seq][cmd][payload…] con relleno de ceros hasta múltiplo de 4
len = tamaño(inner) + 4
```

- CRC16-Modbus: polinomio `0xA001` reflejado, inicio `0xFFFF`.
- CRC32: el estándar zlib.

## Tipos de paquete (inner[0])

| Valor | Tipo |
|---|---|
| 35 / 37 | Comando |
| 36 / 38 | Respuesta: `payload = [seq de origen][estado][cuerpo…]`, con estado 1 = OK y 2 = pendiente |
| 40 | Tiempo real: `ts u32 @2`, `FC @8`, `n R-R @9`, `R-R u16 @10…` |
| 47 | Histórico: el byte 1 es la versión de registro (`v18` = resumen por segundo) |
| 48 / 53 / 54 | Evento: `inner[2]` = número, `ts @4` |
| 49 / 56 | Metadatos de descarga: `1` inicio, `2` fin de bloque, `3` completado |

## Comandos usados

| Opcode | Nombre | Cuerpo |
|---|---|---|
| 3 | TOGGLE_REALTIME_HR | `01` / `00` |
| 10 | SET_CLOCK | `u32 segundos · u16 subseg (1/32768 s) · 00 00` |
| 19 | RUN_HAPTIC_PATTERN_MAVERICK | `01 2F 98 00×8 bucles` |
| 20 | ABORT_HISTORICAL_TRANSMITS | `00` |
| 22 | SEND_HISTORICAL_DATA | vacío |
| 23 | HISTORICAL_DATA_RESULT | `01` + token de 8 bytes (inner 13..20 del fin de bloque) |
| 26 | GET_BATTERY_LEVEL | `01` → `cuerpo[0]` = % |
| 66 / 69 | SET_ALARM_TIME / DISABLE_ALARM | revisión 4 (20 bytes) / `02 FF` |
| 145 | GET_HELLO | `01` → serie, firmware, reloj, batería |

Bloqueados siempre: 25 (FORCE_TRIM), 29 y 32 (reinicio), 36–38, 45 y 142–144 (firmware),
77 (renombrar), 99 (fuel gauge), 115–120 (configuración persistente), 123 y 146.

## Descarga del histórico

1. `SET_CLOCK`, siempre antes de descargar. Sin reloj, la pulsera descarta datos.
2. `SEND_HISTORICAL_DATA`.
3. La pulsera envía registros tipo 47 y después un METADATA `HISTORY_END` con el token.
4. **Guardar** el bloque y después enviar `HISTORICAL_DATA_RESULT(01 + token)`.
5. Repetir hasta `HISTORY_COMPLETE`. Si pasan 10 s sin datos: `ABORT` y cerrar.

Nunca confirmar un bloque que no se ha guardado: la confirmación permite a la pulsera liberarlo.

## Registro v18 (1 por segundo)

Los offsets son relativos a `inner`.

| Offset | Campo |
|---|---|
| 3 | índice de registro u32 |
| 7 | unix u32 |
| 14 | FC |
| 15 / 16 | nº de R-R (≤4) / R-R u16 ms |
| 25 | flags (bit 4 = fuera de la muñeca) |
| 32 | calidad de señal (255 = limpia) |
| 33 | aceleración dinámica f32 (g) |
| 37 / 41 / 45 | gravedad x/y/z f32 (g) |
| 49 | contador de pasos u16 |
| 55 | actividad (0 quieto / 1 andar / 2 correr) |
| 65 | temperatura de la piel u16 / 100 → °C |
| 73 | estado de sueño de la pulsera (bits 4–5) |
| 74 | SpO₂ % (solo durmiendo; 70–100) |
| 98–99 | líneas base ópticas (0 = fuera de la muñeca) |
| 100–101 | amplitudes (128/128 = señal pobre) |

## Fuentes

- `whoop-rs`, `noop` (PROTOCOL.md), `OpenStrap/protocol`, `whoop5-protocol`, `goose`.
- «Cracking the WHOOP 5.0 over Bluetooth» (Alec Jude Wilson).
