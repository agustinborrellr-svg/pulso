# Inteligencia de Pulso

Métricas derivadas que no repiten las puntuaciones de WHOOP, sino que estudian **cómo responde tu
cuerpo, cómo cambia esa respuesta y qué puede anticipar cambios**. Código en
`Packages/PulsoKit/Sources/PulsoIntelligence`, tests en `Tests/PulsoIntelligenceTests`.

Parte de la especificación «WHOOP Intelligence Layer» y la mejora en tres puntos:

1. **Más resolución.** La especificación asume la API de WHOOP (resúmenes, FC por minuto). Pulso
   tiene datos por segundo: R-R, movimiento, temperatura. Por eso puede medir la recuperación de la
   FC a 60 y 120 s o la deriva cardíaca, que con la API no son fiables.
2. **Menos métricas redundantes.** Las 25 se agrupan en 7 piezas que comparten cálculos (la misma
   desviación alimenta coherencia, sorpresa, deuda y respuesta a la carga).
3. **Validación incorporada.** Cada métrica lleva fórmula, versión, tamaño de muestra y confianza, y
   devuelve «datos insuficientes» en vez de inventar. Las predicciones se validan solo hacia atrás y
   se comparan con una referencia simple.

## Piezas

| Pieza | Métricas de la especificación | Qué hace |
|---|---|---|
| `Deviation` | F coherencia, B deuda, W sorpresa (constantes) | Vector nocturno (ln VFC, FC reposo, respiración, temperatura) estandarizado frente a 28 noches (mediana/MAD, mínimo 14). Distancia de Mahalanobis con covarianza contraída un 30 % hacia la identidad → coherencia = percentil empírico de D² entre las 28 noches de referencia (χ²₄ solo para la cola por encima de la peor noche). «Referencia completa» = 28 noches; si mezcla noches importadas se avisa. D⁺ = desviación solo en la dirección desfavorable (ponderada 0,4/0,3/0,15/0,15). Deuda: PD = 0,6·PD₋₁ + max(0, D⁺ − 1) |
| `LoadResponse` | A velocidad, G eficiencia, H huella, M consistencia, D adaptación, O techo | Día exigente = esfuerzo ≥ max(12, tu p75) o entreno ≥ 8. Se sigue D⁺ de las noches siguientes hasta < 1 σ (interpolado). Coste = Σ D⁺ fuera de rango. Huella por deporte × intensidad. RCS = 100·exp(−CV). Adaptación = pendiente coste ~ fecha + esfuerzo con IC 90 %. Techo = codo de una recta con bisagra continua (≥ 20 eventos); los días que no se recuperan en 5 noches cuentan como «≥ 5» (censurados), no se descartan. «No se ve límite» es un resultado. Los días encadenados se apartan |
| `WorkoutAnalysis` | J curva FCR, I deriva, L reserva | FCR60/120 con ventanas de 10 s y cobertura ≥ 60 %; τ por ajuste log-lineal de los 2 primeros minutos; minutos hasta reposo + 10 % de reserva. Deriva solo si cadencia (±6 %) o movimiento (±15 %) estables tras 10 min. Reserva media, mejor minuto y tiempo > 90 % (aproximado si la FC máx es estimada) |
| `Rhythms` | E disrupción, P fragmentación, Q eficiencia del sueño, R horario, K coste cardíaco | SRI (Phillips 2017) minuto a minuto en 14 días; jet lag social; índice compuesto. Momento del mínimo de FC nocturno (sustituye a Q, más interpretable). Regresión recuperación ~ horas + despertares + desfase de hora de acostarse con IC 90 %. Coste cardíaco = latidos de más despierto fuera de entrenos y siestas |
| `HabitImpact` | S impacto, U resiliencia | Diferencia de Welch con IC 90 % (mín. 4 días con y 4 sin), cambio de VFC y de D⁺, noches hasta normalizar |
| `RecoveryModel` | T predictor, X modelo personal, V predictibilidad, W sorpresa, Y gemelo | Ridge (λ = 2) sobre recuperación y esfuerzo de hoy, deuda de sueño, deuda fisiológica, horas de sueño y hábitos. Validación *rolling origin*. PP = 1 − MAE/MAE_ref (ref = media de 7 días). Intervalo 80 % con el error fuera de muestra. Escenarios hipotéticos con el mismo modelo |
| `Intelligence.adaptationLag` | N desfase | Correlación cruzada semanal Δesfuerzo → Δln VFC, desfases 0–4 semanas, IC por remuestreo (≥ 12 semanas) |

## Límites honestos

- Todo es asociación con tus propios datos. Un hábito puede coincidir con otros cambios: el test
  `testHabitImpactWithInterval` muestra cómo un diseño desequilibrado crea efectos falsos.
- Las cifras no están validadas clínicamente ni son diagnósticos.
- Con pocas semanas, muchas métricas aparecen como «datos insuficientes»: es lo esperado.
- El simulador usa relaciones observadas; no garantiza el resultado.

## Tests (casos con respuesta conocida)

- χ², t de Student, inversa y regresión frente a valores exactos.
- Una «enfermedad» simulada da coherencia < 1 y D⁺ > 2,5; una combinación rara (VFC baja con FC
  baja) se detecta conjuntamente sin contar como desfavorable.
- Días exigentes con recuperación conocida: 1–3 noches, coste > 1, VFC −15 % o más.
- Alcohol con −25 puntos: efecto claro e IC por debajo de 0; hábito sin efecto con diseño equilibrado:
  IC que cruza el 0.
- Modelo con coeficientes conocidos: supera a la referencia en más de un 20 % y los escenarios se
  mueven en la dirección correcta.
- SRI ≈ 100 con horarios idénticos y < 75 con horarios caóticos; coste por despertar ≈ −3.
- Curva de FC con τ = 60 s: FCR60 ≈ 60 lpm y τ ≈ 60 s; deriva solo en esfuerzo estable.

## Cambios del 30-oct-2026

- **Hábitos**: «sin» = solo días en que se preguntó ese hábito; «claro» exige IC 90 % sin el 0 **y** sobrevivir a Benjamini–Hochberg (q < 0,10) entre todos los hábitos. Se muestran n y q.
- **Sensibilidad al horario**: usa también noches importadas (con término por fuente). **Coste de cada despertar**: solo noches medidas por Pulso.
- **Coste cardíaco**: compara solo días completos; hoy se muestra «en lo que va de día» sin %.
- **Explorador**: empareja por fecha; r con IC 90 % (Fisher z); «relación» solo si el IC excluye 0.
- **Simulador**: hábitos con < 5 días «sí» quedan fuera del modelo.
- **Recuperación del pulso por entreno**: solo se cachea un resultado final; sin pulso → «sin datos de pulso».
- Cada análisis tiene «Cómo se calcula» (`MetricGuide`): tipo de afirmación, definición, fórmula, datos, periodo, n, confianza, lectura y limitaciones.
