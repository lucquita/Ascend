# Fase 4 — Aura y gamificación · Resultado

**Estado: completada.** Fecha: 2026-08-14.

---

## 1. Verificación

| Comprobación | Estado | Evidencia |
|---|---|---|
| Formato | ✅ | `dart format --set-exit-if-changed .` → 0 cambios |
| Análisis estático | ✅ | `dart analyze --fatal-infos .` → *No issues found* |
| Tests de Dart | ✅ | **310** (+11 del DTO de Aura) |
| Tests de Functions | ✅ | **63** (27 + **36 nuevos**: motor de Aura y rachas) |
| Tests de reglas | ✅ | **97** (89 + **8 nuevos** de seguridad de Aura) |
| Lint + `tsc` | ✅ | limpios |

**Total: 470 tests en verde.** Desde 415 en la Fase 3, se agregaron **55**.

---

## 2. Qué quedó construido

```
backend/functions/src/
├── config/aura-rules.ts             reglas por defecto + parseo tolerante
├── services/aura-service.ts         LÓGICA PURA: recompensa, tope, racha, niveles
├── triggers/on-mission-write.ts     transacción idempotente: ledger + saldo + racha
└── scheduled/streak-checker.ts      barrido diario que rompe rachas perdidas

packages/ascend_data/lib/src/
├── dtos/aura_dto.dart               solo lectura, sin métodos de escritura
├── datasources/remote/firestore_aura_datasource.dart
└── repositories/aura_repository_impl.dart

apps/ascend_mobile/lib/features/aura/
├── application/aura_controller.dart
└── presentation/screens/aura_screen.dart   saldo · nivel · evolución · ledger

backend/firestore.rules           + match /auraUsage/{day}
backend/firestore.indexes.json    + índice del ledger por fecha
backend/tests/                    + 8 casos de seguridad de Aura
```

La ruta `/profile/aura` ya no es un placeholder.

---

## 3. Cómo se garantiza que el Aura no se pueda manipular

Es el ADR-003 llevado a código. Cuatro defensas, todas con test:

**① El cliente solo escribe `mission.status`.** Las reglas rechazan escribir
`users.aura`, `auraLedger` y `auraUsage`. Hay 8 tests que lo verifican,
incluido el ataque de colar el saldo dentro de una edición legítima de perfil.

**② La recompensa se calcula en el servidor** a partir de `config/auraRules`,
que solo el admin edita. El cliente ni siquiera puede proponer `auraReward`
(regla `absent()`, verificada desde la Fase 2B).

**③ La operación es idempotente.** El id del asiento es determinístico:
`mission_completed__{missionId}`. Si ya existe, la transacción no otorga nada.
Eso cubre los dos casos reales: el doble toque en la interfaz y el **reintento
automático del runtime de Functions**, que sin esto duplicaría la recompensa
cada vez que una ejecución fallara a mitad de camino.

**④ Todo ocurre en una transacción.** Hay que leer saldo, asiento previo y
consumo del día, y escribir tres documentos. Sin transacción, dos misiones
completadas a la vez leerían el mismo saldo y una pisaría a la otra: el Aura de
una de las dos desaparecería.

### Tope diario y multiplicadores

- **Tope de 500/día.** Crear 200 misiones triviales y completarlas no da el
  nivel máximo. Con el tope agotado la recompensa es 0, nunca negativa.
- **El asiento se escribe igual con recompensa 0**, porque es lo que vuelve
  idempotente la operación y deja rastro de que la misión ya se contabilizó.
- **Multiplicadores de racha** (×1.1 a los 3 días, hasta ×2 a los 30). Un
  multiplicador configurado por debajo de 1 se eleva a 1: bonificar con 0.5
  castigaría por tener racha.
- **La evidencia suma antes del multiplicador**, para que documentar con racha
  alta rinda más que documentar sin ella.
- **La recompensa siempre es entera**: 25 × 1.1 = 27, no 27.5. Un saldo con
  decimales rompería el ledger.

### Rachas

`nextStreak` distingue tres casos y cada uno tiene test:

| Situación | Resultado |
|---|---|
| Misma fecha que la última actividad | La racha **no cambia** |
| Día siguiente | Suma uno |
| Salto mayor, o sin actividad previa | Vuelve a 1 |

El primer caso importa más de lo que parece: si cada misión sumara un día, diez
misiones en una tarde darían una racha de diez días. Las fechas se comparan en
**UTC** para que el tope y la racha no dependan del huso del dispositivo.

---

## 4. Decisiones

### 4.1 La lógica está separada del trigger

`aura-service.ts` no importa Firestore. Las reglas que hacen que la gamificación
sea justa son exactamente las que hay que poder testear exhaustivamente, y
hacerlo contra el emulador sería lento y frágil. **30 tests puros** cubren la
tabla completa; el trigger se queda solo con la transacción.

### 4.2 Un `config/auraRules` roto no puede tumbar el motor

`parseAuraRules` normaliza campo por campo: lo ausente o con el tipo equivocado
cae al default, los tramos y niveles se ordenan aunque vengan desordenados. Un
documento a medio editar desde el panel degrada el balance, no rompe la app.

### 4.3 La tabla de niveles es rala

Define 1, 2, 3, 5, 7, 10 y 15. `levelFor` devuelve el nivel más alto alcanzado y
mide el avance contra el **siguiente tramo definido**, no contra el siguiente
número. En el último nivel informa avance completo en vez de dividir por cero.

### 4.4 `auraUsage` es legible pero no escribible

Se puede leer para mostrar "te queda X de tope por hoy". Escribirlo sería
resetearse el tope y farmear sin límite, así que es `write: if false`.

---

## 5. `streakChecker`: por qué hace falta una tarea programada

Una racha se pierde por **inacción**, y la inacción no dispara ningún trigger.
Sin este barrido, alguien que dejó de usar la app durante un mes seguiría viendo
su racha de 30 días intacta hasta volver a completar algo — y la gamificación
perdería el único mecanismo que empuja a volver todos los días.

Corre una vez al día a las 03:00 UTC y solo mira a quien tenga
`currentStreak > 0`, así que el costo crece con los usuarios activos y no con el
total registrado.

**La racha se rompe a los dos días, no a uno.** Un solo día de diferencia es
"ayer": la persona todavía está a tiempo de completar algo hoy. Romperla a las
00:01 castigaría a quien entrena de noche. `longestStreak` no se toca nunca:
perder la racha actual no borra el récord histórico.

---

## 6. Lo que no entró

- **Pantallas 33–35**: estadísticas detalladas, logros y ranking. El ranking
  además depende de `publicProfiles`, que se completa con la comunidad (Fase 5).
- **Animación de celebración con háptica** al completar una misión.
- **Historial de misiones en pantalla.** `getHistory` está implementado y
  testeado desde la Fase 2B; falta la vista paginada.
- **Aviso previo de racha en riesgo.** Es una notificación push y depende de FCM
  (Fase 7). `streakChecker` ya identifica a quién avisarle.

---

## 7. Configuración pendiente

Se suma el despliegue del trigger, la tarea programada y el índice nuevo. La
tarea programada crea un job en **Cloud Scheduler**, que en la capa gratuita
admite hasta 3 jobs:

```bash
cd backend && firebase deploy --only firestore:rules,firestore:indexes,functions
```

Opcionalmente, sembrar `config/auraRules` para poder ajustar el balance sin
publicar. Si el documento no existe, el motor usa los valores por defecto.
