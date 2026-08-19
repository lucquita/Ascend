# Fase 2A — Objetivos · Resultado

**Estado: completada.** Fecha: 2026-08-14.
Toolchain de esta máquina: Flutter 3.44.1 · Dart 3.12.1 · Node 20.19 · JDK 21 portable.

> El roadmap original define la Fase 2 como "Objetivos **y** misiones". Se partió
> en **2A (Objetivos)** y **2B (Misiones)** por indicación del product owner.
> Este documento cubre 2A.

---

## 1. Verificación

| Comprobación | Estado | Evidencia |
|---|---|---|
| Formato | ✅ | `dart format --set-exit-if-changed .` → 0 cambios |
| Análisis estático | ✅ | `dart analyze --fatal-infos .` → *No issues found* |
| Tests de Dart | ✅ | **234** (39 core · 66 domain · 56 data · 28 ui · 45 mobile) |
| Tests de Functions | ✅ | 27 con vitest |
| Lint de Functions | ✅ | `eslint` sin errores |
| Compilación de Functions | ✅ | `tsc` strict sin errores |
| Tests de reglas | ✅ | **72** contra el emulador de Firestore (ver §5) |

**Total: 333 tests en verde.** Partiendo de 264 en la Fase 1, se agregaron
**69**: 19 de casos de uso, 20 de DTOs, 12 de pantallas, 3 de App Check
(BUG-001) y 15 de reglas de seguridad.

Es la primera vez que las tres suites corren juntas y en verde en esta máquina.

---

## 2. Qué quedó construido

```
packages/ascend_domain/lib/src/usecases/
└── goal_usecases.dart          7 casos de uso + validación compartida

packages/ascend_data/lib/src/
├── dtos/goal_dto.dart          escrituras parciales, lectura tolerante
├── dtos/category_dto.dart      catálogo multi-idioma
├── datasources/remote/         firestore_goal_ds · firestore_category_ds
├── repositories/               GoalRepositoryImpl · CategoryRepositoryImpl
└── providers/                  grafo de DI + `categoriesProvider`

apps/ascend_mobile/lib/features/goals/
├── application/goals_controller.dart    filtro · listas · GoalController
└── presentation/
    ├── screens/    goals_list · goal_form (alta y edición) · goal_detail
    └── widgets/    GoalCard · GoalStatusChip · MilestoneTile

packages/ascend_ui/lib/src/atoms/
└── ascend_text_field.dart      promovido desde la feature de auth

backend/
├── functions/src/triggers/on-goal-delete.ts    cascada con BulkWriter
├── functions/scripts/seed-categories.mjs       catálogo inicial (10 categorías)
├── firestore.indexes.json                      +3 índices
└── tests/firestore.rules.test.js               +15 casos
```

Las rutas `/goals`, `/goals/new`, `/goals/:goalId` y `/goals/:goalId/edit` ya no
son placeholders.

---

## 3. Decisiones que conviene tener registradas

### 3.1 El DTO escribe mapas parciales, nunca un `toJson()` completo

Las reglas de `goals` prohíben tres campos al cliente:

```
allow create: ... && absent('progress') && absent('auraEarned');
allow update: ... && unchanged('ownerId')
                  && unchanged('progress') && unchanged('auraEarned');
```

`absent()` comprueba la **presencia de la clave**, no su valor: mandar
`'progress': null` en el alta hace fallar la escritura entera igual que mandar
un progreso inventado. Por eso `GoalDto.toCreate` no incluye esas claves y
`toUpdate` tampoco incluye `ownerId`.

Es la misma trampa en la que ya cayó la Fase 1 con `lastLoginAt` (§3.2 de su
documento). Hay **dos tests dedicados** que recorren la lista de campos
prohibidos y fallan si alguno aparece.

### 3.2 `onGoalDelete` se implementó ahora, aunque las misiones lleguen en 2B

Las reglas permiten al cliente borrar su objetivo, pero no pueden obligarlo a
borrar las misiones asociadas. Si lo hiciera la app, un corte de red a mitad del
recorrido dejaría misiones apuntando a un `goalId` inexistente — y como la
pantalla "Hoy" consulta `users/{uid}/missions` sin filtrar por objetivo
(ADR-005), esas misiones seguirían apareciendo sin forma de abrirlas ni
borrarlas.

Escribirlo ahora cuesta lo mismo y evita que todo objetivo borrado durante la
Fase 2B genere basura.

Usa `BulkWriter` y no una transacción: una transacción admite 500 operaciones y
un objetivo generado por IA puede tener cientos de misiones.

### 3.3 Las transiciones de estado son una máquina explícita

`ChangeGoalStatusUseCase` valida la transición en lugar de aceptar cualquier
estado. Dos casos que se rechazan a propósito:

- **pausado → completado.** Habría que reactivarlo primero. Completar desde
  pausa saltea el trabajo real y es la vía obvia para inflar el contador de
  objetivos completados.
- **completado → activo.** El Aura ya se otorgó; revertirla es una operación de
  servidor con su asiento en el ledger, no un botón de pantalla.

### 3.4 Ningún provider devuelve un stream vacío

Un `Stream.empty()` se cierra sin emitir y deja el provider en `AsyncLoading`
**para siempre**: la pantalla se queda con el skeleton girando sin explicar
nada. `goalsProvider` y `goalDetailProvider` emiten un `Failed` tipado cuando no
hay sesión.

Es literalmente el modo de fallo que el producto no admite, y se detectó porque
un test existente empezó a colgarse.

### 3.5 `AuthField` se promovió al design system

El alta de objetivos necesitaba el mismo campo de texto que las pantallas de
autenticación. En vez de copiarlo, se creó `AscendTextField` en `ascend_ui`
—donde el documento de arquitectura lo ubicaba desde el principio— y `AuthField`
quedó como envoltorio que delega. Las pantallas de la Fase 1 y sus tests no se
tocaron.

### 3.6 `createGoalWithMissions` queda pendiente, con fallo tipado

El alta atómica de objetivo + misiones es el cierre del asistente con IA
(Fase 6) y necesita el DTO de misiones, que llega en 2B. Devuelve un
`ValidationFailure` con mensaje propio en lugar de escribir solo el objetivo:
dejar un objetivo vacío y perder sus misiones en silencio sería peor que fallar.
Ninguna pantalla de 2A lo invoca.

---

## 4. Índices agregados

Tres consultas nuevas necesitaban índices que no existían:

| Colección | Campos | Consulta |
|---|---|---|
| `goals` | `categoryId ASC, updatedAt DESC` | Filtrar por categoría sin filtrar estado |
| `categories` | `active ASC, order ASC` | Catálogo activo ordenado |

Hay que desplegarlos antes de usar los filtros contra Firebase real:

```bash
cd backend && firebase deploy --only firestore:indexes
```

---

## 5. Tests de reglas

**72 tests ejecutados, 72 en verde, 0 fallidos.**

Se agregaron **15 casos** en dos bloques: *Objetivos — campos que solo escribe
el servidor* y *Catálogo de categorías*. Cubren los ataques que importan:
crearse progreso, otorgarse Aura, crear un objetivo a nombre de otro, esconder
un campo prohibido entre campos permitidos, cambiar el dueño, leer objetivos
ajenos y editar el catálogo global siendo un usuario común.

Esta máquina tiene JDK 17 y el emulador exige 21+. Para esta corrida se usó un
**JDK 21 portable** descargado a una carpeta temporal de sesión, que no
sobrevive al reinicio. Para dejarlo permanente:

```bash
winget install --id Microsoft.OpenJDK.21 -e
```

`firebase-tools` tampoco estaba instalado; se instaló localmente en
`backend/tests/node_modules` sin tocar el `package.json` del repositorio. En CI
esto ya está resuelto (`setup-java` con 21 + `npm install -g firebase-tools`).

---

## 6. Configuración que depende de vos

1. **Sembrar el catálogo de categorías.** Sin categorías no se puede crear un
   objetivo, y la pantalla lo dice explícitamente en vez de mostrar una fila
   vacía.

   ```bash
   cd backend/functions
   GOOGLE_APPLICATION_CREDENTIALS=/ruta/clave.json GOOGLE_CLOUD_PROJECT=ascend-dev node scripts/seed-categories.mjs
   ```

2. **Desplegar índices, reglas y la función nueva:**

   ```bash
   cd backend && firebase deploy --only firestore:rules,firestore:indexes,functions
   ```

3. **BUG-001 sigue sin verificarse contra Firebase real.** Ver
   [06-BUGS-CONOCIDOS.md](06-BUGS-CONOCIDOS.md).

---

## 7. Lo que no entró

- **Misiones.** Fase 2B.
- **Reordenamiento de hitos por arrastre.** Se pueden agregar y quitar; el orden
  se asigna por posición de alta. El drag & drop está en los entregables de la
  Fase 2 para misiones, no para hitos.
- **Filtro por categoría en la UI.** El repositorio, el caso de uso y el índice
  lo soportan; la barra de filtros solo expone estados. Enchufarlo es agregar
  una fila de chips que lea `categoriesProvider`.
- **Textos en inglés.** Igual que en las fases anteriores: las claves ARB están,
  las pantallas usan literales en español. El roadmap lo ubica en la Fase 9.
