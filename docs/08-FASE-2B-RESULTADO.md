# Fase 2B — Misiones · Resultado

**Estado: completada.** Fecha: 2026-08-14.

---

## 1. Verificación

| Comprobación | Estado | Evidencia |
|---|---|---|
| Formato | ✅ | `dart format --set-exit-if-changed .` → 0 cambios |
| Análisis estático | ✅ | `dart analyze --fatal-infos .` → *No issues found* |
| Tests de Dart | ✅ | **272** |
| Tests de reglas | ✅ | **83** contra el emulador |
| Tests de Functions | ✅ | 27 con vitest |
| Lint + `tsc` de Functions | ✅ | limpios |

**Total: 382 tests en verde.** Desde 333 en la Fase 2A, se agregaron **49**:
23 de casos de uso, 15 de DTO y 11 de reglas de seguridad.

---

## 2. Qué quedó construido

```
packages/ascend_domain/lib/src/
├── enums/enums.dart                 + MissionBudget
├── entities/mission.dart            + campo budget
└── usecases/mission_usecases.dart   9 casos de uso + DailyProgress + helpers

packages/ascend_data/lib/src/
├── dtos/mission_dto.dart            escrituras parciales sin auraReward
├── datasources/remote/firestore_mission_datasource.dart
└── repositories/mission_repository_impl.dart

apps/ascend_mobile/lib/features/missions/
├── application/missions_controller.dart
└── presentation/
    ├── screens/  today · mission_form · mission_detail
    └── widgets/  MissionTile · DailyProgressHeader

backend/firestore.indexes.json       +4 índices de misiones
backend/tests/                       +11 casos de reglas
```

Las rutas `/home` (Hoy), `/goals/:goalId/missions/new` y `/missions/:missionId`
ya no son placeholders. El detalle del objetivo muestra sus misiones embebidas.

---

## 3. Decisiones

### 3.1 `MissionBudget` es nuevo en el modelo

El roadmap pedía presupuesto (gratis/bajo/medio/alto) y el modelo de datos no lo
tenía. Se agregó como enum del dominio y campo de `Mission`.

**No influye en la recompensa de Aura**, y eso es deliberado: si pagar más diera
más progreso, la gamificación se volvería un ranking de poder adquisitivo. La
recompensa la determina `MissionDifficulty`. Ante un valor desconocido degrada a
`free`, porque mostrar de más en un filtro es preferible a esconderle a alguien
una misión que sí podía hacer.

### 3.2 `auraReward` nunca viaja desde el cliente

Mismo patrón que `progress` en objetivos, y por el mismo motivo (ADR-003): si el
cliente pudiera proponer la recompensa, se otorgaría la que quisiera. `toCreate`
no incluye la clave —`absent()` mira la presencia, así que mandarla en `null`
fallaría igual— y ninguna escritura de estado la toca.

Hay tests en tres niveles: DTO, reglas de Firestore, y un caso de reglas que
verifica el ataque realista de **colar `auraReward` junto a un cambio legítimo de
estado**, que es como se intentaría de verdad.

### 3.3 Completar relee el documento antes de escribir

`MissionRepositoryImpl.completeMission` lee la misión y evalúa `canComplete`
sobre el estado real, no sobre lo que la pantalla tenía cacheado. Sin eso, dos
toques rápidos o dos dispositivos podrían completar la misma misión dos veces y
disparar el trigger de Aura por duplicado.

Cuesta una lectura extra por completado. Es barato frente a un exploit que
rompería el ranking.

### 3.4 `createGoalWithMissions` quedó completo

En la Fase 2A devolvía un fallo tipado porque faltaba `MissionDto`. Ahora escribe
objetivo y misiones en un único `WriteBatch`, y las misiones heredan `goalTitle`
y `categoryId` del objetivo. Es el cierre del asistente con IA (Fase 6).

### 3.5 "Hoy" filtra por `pending`, no por "abiertas"

Firestore no admite `whereIn` combinado con una desigualdad sobre otro campo sin
un índice por combinación. La consulta usa `status == pending` y
`dueDate <= fin del día`, que se resuelve con el índice
`missions(status, dueDate, order)` en **una sola lectura**.

Consecuencia visible: una misión marcada como "en curso" no aparece en Hoy. Se
la ve desde el objetivo. Si esto molesta en uso real, la salida es agregar un
campo booleano `isOpen` mantenido por el servidor, no romper la consulta única.

### 3.6 Recurrencia: se persisten días como enteros

El documento de modelo de datos proponía `days: ["mon","wed","fri"]`. La entidad
`Recurrence` ya usaba `List<int> weekdays` (1 = lunes … 7 = domingo), que es lo
que Dart devuelve en `DateTime.weekday`. Se persiste como enteros para no
traducir en cada lectura. **Desvío consciente del diseño original.**

---

## 4. Bugs encontrados durante la implementación

### 4.1 `AscendSkeletonList` dentro del detalle rompía el layout

La sección de misiones usaba `AscendSkeletonList` como estado de carga. Ese
widget es un `ListView`, y anidarlo dentro del `ListView` del detalle produce
*"Vertical viewport was given unbounded height"* — pantalla rota mientras cargan
las misiones. Lo detectó un test de widget, no una revisión visual. Se reemplazó
por una `Column` de skeletons.

### 4.2 `Page` del dominio colisiona con `Page` de Flutter

`ascend_domain` exporta `Page<T>` (paginación) y Flutter exporta `Page`
(navegación). Cualquier archivo que importe ambos no compila. Por ahora se
resuelve con `hide Page` donde hace falta. **Vale renombrarlo a `Paginated<T>` en
la Fase 10**: es un cambio mecánico y evita el tropiezo cada vez que alguien
escriba un test nuevo.

---

## 5. Lo que no entró

- **Reordenamiento por arrastre.** El caso de uso, el repositorio y la escritura
  en lote están hechos y testeados; falta el `ReorderableListView` en pantalla.
- **Historial paginado.** `getHistory` con cursores está implementado y testeado;
  la pantalla queda como placeholder porque cobra sentido junto al Aura (Fase 4).
- **Recurrencia en la UI.** El modelo y la persistencia la soportan; el
  formulario todavía no la ofrece.
- **Progreso del objetivo calculado.** `goal.progress` lo tiene que escribir el
  trigger `onMissionWrite`, que llega con el Aura (Fase 4). Hasta entonces el
  detalle dice "Sin progreso calculado" en vez de mostrar un 0% engañoso.

---

## 6. Configuración pendiente

Se suman **4 índices de misiones** a los de la Fase 2A:

```bash
cd backend && firebase deploy --only firestore:rules,firestore:indexes,functions
```

Sigue pendiente el seed de categorías y la verificación de BUG-001 contra
`ascend-dev`. Ninguno bloquea el desarrollo ni los tests.
