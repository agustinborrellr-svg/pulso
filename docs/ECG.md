# ECG en Pulso (preparado para la WHOOP MG)

La WHOOP 5.0 no tiene electrodos. La MG sí, pero su protocolo de ECG por Bluetooth **no está
documentado públicamente**. Pulso tiene todo lo demás hecho para que activarlo sea rellenar un hueco:

| Pieza | Dónde | Estado |
|---|---|---|
| Detección de latidos (Pan-Tompkins por regiones) | `PulsoECG/ECGAnalysis.swift` | Hecho y probado |
| Calidad de señal y onda P (latido medio) | idem | Hecho y probado |
| Clasificación: sinusal, frecuencia baja/alta, irregular, no concluyente | idem | Hecho y probado |
| Simulador (sinusal y fibrilación auricular) | idem | Hecho |
| PDF en papel milimetrado (25 mm/s, 10 mm/mV) | `PulsoECG/ECGReport.swift` | Hecho y validado |
| Guardado en SQLite | `PulsoStore/Database.swift` (tabla `ecg`) | Hecho |
| Importación de ECG del Apple Watch | `App/Health/HealthExporter.swift` | Hecho |
| Pantallas (historial, grabar 30 s, trazado, compartir PDF) | `App/Views/ECGView.swift` | Hecho |
| **Decodificador de tramas de la MG** | `PulsoECG/ECGCapture.swift` → `MGECGDecoder` | **Pendiente de capturas** |
| **Comando para iniciar/parar el ECG en la MG** | `WhoopProtocol/Commands.swift` | **Pendiente** |

## Cómo completar el decodificador con una MG

1. En Pulso: *Más → Avanzado → Herramientas de laboratorio → Laboratorio*.
2. Activa **Grabar tramas** y **Grabar también las conocidas**.
3. Falta saber qué comando arranca el ECG. La pulsera solo admite un emparejamiento, así que no se
   puede espiar a la app oficial desde Pulso. Hay dos caminos: capturar con un sniffer BLE
   (nRF52840 + Wireshark) mientras la app oficial hace un ECG, o buscar el comando en las apps open
   source (`OpenStrap`, `noop`) cuando lo publiquen. Con el comando, el Laboratorio graba las tramas
   que lleguen.
4. Con las tramas: identifica el tipo de paquete (candidato: 43 `REALTIME_RAW_DATA`), el byte donde
   empiezan las muestras, su tamaño (16 o 24 bits) y la escala (µV por unidad).
5. Rellena `MGECGDecoder` (`sampleRate`, `packetType`, `firstSampleOffset`, `bytesPerSample`,
   `microvoltsPerLSB`) y, si hace falta, añade el opcode de inicio a `Opcode` (nunca uno de los
   prohibidos).
6. `ecgAvailable` pasa a ser verdadero solo y aparece el botón «Hacer un ECG».

El test `testMGDecoderIsInertUntilConfigured` muestra cómo se comporta una vez configurado.

> Pulso no es un dispositivo médico. El ECG es orientativo y no detecta infartos.
