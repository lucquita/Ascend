# Fase 6 — Inteligencia artificial · Resultado

**Estado: completada a nivel de código. Falta la API key** (ver §6).
Fecha: 2026-08-14.

---

## 1. Verificación

| Comprobación | Estado | Evidencia |
|---|---|---|
| Formato | ✅ | `dart format --set-exit-if-changed .` → 0 cambios |
| Análisis estático | ✅ | `dart analyze --fatal-infos .` → *No issues found* |
| Tests de Dart | ✅ | **356** (+15) |
| Tests de Functions | ✅ | **90** (+27 del motor de IA) |
| Tests de reglas | ✅ | 103 |
| Lint + `tsc` | ✅ | limpios |

**Total: 549 tests en verde.** Desde 507 en la Fase 5, se agregaron **42**.

---

## 2. Qué quedó construido

```
backend/functions/src/
├── config/prompts.ts               prompts versionados + responseSchema
├── services/ai-schemas.ts          VALIDACIÓN ESTRICTA de la salida (pura)
├── services/ai-quota.ts            tope diario y política de reintegro (pura)
├── services/gemini-service.ts      cliente REST con timeout y errores tipados
└── callable/generate-goal-plan.ts  cuota → generación → validación → auditoría

packages/ascend_domain/lib/src/usecases/ai_usecases.dart
    ProposedPlan · GenerateGoalPlanUseCase · MaterializePlanUseCase
    + biblioteca de plantillas por categoría

packages/ascend_data/lib/src/repositories/ai_repository_impl.dart
apps/ascend_mobile/lib/features/ai/presentation/screens/ai_wizard_screen.dart
```

La ruta `/goals/new/generating` ya no es un placeholder, y la lista de objetivos
tiene un acceso al asistente.

---

## 3. ADR-002: la key nunca sale del servidor

El cliente manda el objetivo a una **llamable con App Check**; la función lee la
key de Secret Manager y llama a Gemini. La app no conoce el endpoint del modelo
ni el prompt.

Si la key viajara en el binario, se extraería de un APK en cinco minutos —y en
web está literalmente en el JS servido—. El modo de fallo típico es una factura
de miles de dólares en 48 horas.

Detalle menor pero deliberado: la key va en el **header** `x-goog-api-key`, no en
el query string. Una key en la URL queda en los logs de acceso de cualquier proxy
intermedio.

---

## 4. Lo que hace la función además de generar

**① Reserva la cuota antes de llamar.** Si se contara después, diez peticiones
simultáneas verían cuota libre y se ejecutarían las diez. El tope son 20
generaciones por día y por persona.

**② Revalida la respuesta contra un schema propio.** Se le pide a Gemini
`responseSchema`, pero eso reduce la tasa de error, no la elimina: un título
vacío, una duración de 10.000 minutos o una dificultad inventada pasan el schema
de tipos. Lo que llega se convierte en misiones de una persona — si no se valida,
la basura del modelo se vuelve datos del producto.

**③ Corrige lo que el prompt pide y el modelo no siempre cumple.** Se descartan
duplicados y las misiones que exceden el presupuesto: devolverle a alguien que
dijo "gratis" una misión que cuesta plata es peor que devolverle una menos.

**④ Registra costo, tokens y latencia en `aiJobs`.** Sin eso no se puede
responder cuánto cuesta la IA por usuario activo. También se guarda el
`promptVersion`: sin versión, un cambio de prompt es imposible de correlacionar
con un cambio de calidad.

**⑤ Devuelve la cuota si falló.** La persona no recibió nada; cobrarle el intento
sería castigarla por un problema nuestro o del proveedor. Solo el éxito consume.

**⑥ No escribe nada.** Devuelve el plan para que la app lo muestre en una
pantalla de revisión editable. **Un plan generado que se guarda solo es un plan
que nadie leyó**, y termina siendo seis misiones que no se van a hacer.

---

## 5. La regla de oro: con la IA caída, la persona termina igual

`GenerateGoalPlanUseCase` **nunca falla por culpa de la IA**. Timeout, cuota
agotada, respuesta malformada, bloqueo del modelo: todo cae a la **plantilla de
la categoría**, y el asistente sigue adelante.

Hay plantillas propias para fitness, idiomas, lectura, finanzas, bienestar y
creatividad, más una genérica para el resto. Respetan el presupuesto pedido igual
que la IA.

La pantalla **avisa** cuando el plan es de reserva. Hacerlo pasar por generado
sería mentir sobre lo que la persona está mirando.

Un asistente que al fallar deja a alguien frente a un error sin salida es peor
que no tener asistente. Está cubierto por tests: la caída a plantilla, la cuota
agotada, y que una categoría desconocida nunca devuelva una lista vacía.

---

## 6. ⚠️ Configuración pendiente — la API key

**Esto es lo único que falta para que la IA funcione de verdad.** Requiere el
plan Blaze, igual que Storage.

1. Obtener una API key de Gemini en [Google AI Studio](https://aistudio.google.com/apikey).
2. Cargarla en Secret Manager:
   ```bash
   cd backend && firebase functions:secrets:set GEMINI_API_KEY
   ```
3. Desplegar:
   ```bash
   firebase deploy --only functions:generateGoalPlan
   ```

**No la pongas en el repositorio, ni en un `.env`, ni en un `--dart-define`.** El
`.gitignore` ya bloquea `.env`, pero la única forma correcta es Secret Manager.

**Sin la key, la app no se rompe.** `generateStructured` falla rápido y con un
motivo claro (`no-api-key`), el caso de uso cae a la plantilla y el asistente
funciona igual: la persona arma su objetivo con un plan de arranque editable.
Eso es exactamente lo que el diseño busca, así que se puede demostrar el flujo
completo hoy mismo sin gastar un centavo.

---

## 7. Lo que no entró

- **`suggestMissions` y `getMotivation`.** El prompt y el schema de sugerencias
  están escritos y testeados; falta la llamable y su pantalla. `getMotivation`
  es texto libre y aporta menos que las otras dos.
- **Moderación por IA del contenido de la comunidad.** Es la deuda que quedó
  abierta en la Fase 5. Requiere otro prompt y otra llamable.
- **Sugerencia diaria contextual.** Depende de notificaciones (Fase 7).
- **Caché de planes por categoría.** Con 20 generaciones diarias por persona el
  volumen no lo justifica todavía; cuando lo justifique, el lugar natural es
  entre la cuota y la llamada al modelo.
