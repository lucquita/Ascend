# Fase 1 — Autenticación y Perfil · Resultado

**Estado: completada.** Fecha: 2026-08-12.
Toolchain: Flutter 3.44.4 · Dart 3.12.2 · Node 24.14 · Firebase CLI 15.21 · JDK 21.0.12.

---

## 1. Verificación

| Comprobación | Estado | Evidencia |
|---|---|---|
| Formato | ✅ | `dart format --set-exit-if-changed .` → 0 cambios |
| Análisis estático | ✅ | `dart analyze --fatal-infos .` → *No issues found* |
| Tests de Dart | ✅ | **180** (39 core · 47 domain · 33 data · 28 ui · 33 mobile) |
| Tests de reglas | ✅ | **57** contra el emulador de Firestore |
| Tests de Functions | ✅ | **27** con vitest |
| Lint de Functions | ✅ | `eslint` sin errores |
| Compilación de Functions | ✅ | `tsc` strict sin errores |

**Total: 264 tests en verde.** Partiendo de 163 en la Fase 0, se agregaron **101**.

---

## 2. Decisiones que se apartaron del diseño original

Las tres se consultaron y aprobaron antes de implementarlas.

### 2.1 El perfil lo crea una Function, no el cliente

**Qué decía el diseño:** un trigger `onUserCreate` de Auth crearía el perfil, y la unicidad del handle se resolvería "en una transacción junto al perfil".

**Por qué no cierra:** un trigger de Auth no recibe el handle —Auth solo conoce email y `displayName`—, así que no puede reservarlo. Y el cliente tampoco puede: `handles/{handle}` es `write: if false` precisamente para que nadie reserve nombres ajenos. La transacción que el diseño pedía era imposible de escribir desde cualquiera de los dos lados.

**Qué se hizo:** una llamable `registerProfile` que hace todo en una transacción —verifica el handle, escribe `handles/{handle}`, `users/{uid}` y `publicProfiles/{uid}`— y después asigna el claim `role: user`.

Es **idempotente**: si el proceso se corta después de crear la cuenta en Auth, volver a llamarla completa lo que falte en lugar de fallar. Sin eso, esa persona quedaría con una cuenta inutilizable que ni siquiera puede volver a crear, porque su email ya figura registrado.

La regla `allow create` sobre `users/{uid}` se mantiene como defensa en profundidad y tiene tests propios.

### 2.2 `setUserRole` se adelantó de la Fase 8

Sin ella no existe forma de crear el primer administrador salvo un script con credenciales de servicio. Va protegida —solo un admin puede invocarla—, espeja el rol en Firestore, escribe en `auditLog` y **prohíbe que alguien cambie su propio rol**: un admin que se quita el permiso por error dejaría el panel sin nadie que pueda devolvérselo.

### 2.3 Google y Apple quedan fuera de esta fase

Requieren SHA-1, URL schemes y cuenta de Apple Developer, nada configurable sin los proyectos Firebase creados. El contrato ya existe y devuelve un fallo tipado con mensaje propio, así que la UI lo comunica bien en lugar de romperse.

---

## 3. Hallazgos durante la implementación

Cosas que aparecieron al escribir el código y que valía la pena corregir.

### 3.1 El job `functions` de CI venía fallando

`npm run lint` fallaba en `health-check.ts`, un archivo de la Fase 0, por dos accesos sin tipar sobre `DocumentData`. Como CI corre el lint, ese job estaba en rojo desde el primer día. Corregido acotando los tipos a `unknown` y estrechándolos antes de usarlos.

### 3.2 El cliente no puede escribir `lastLoginAt`

La capa de datos llegó a tener un `touchLastLogin`. `lastLoginAt` no está entre los campos que `onlyFields` autoriza, así que esa escritura habría fallado entera con `permission-denied` en cada arranque. Se eliminó el método —la alternativa era aflojar las reglas— y **quedó un test de reglas que lo verifica**, para que no vuelva a colarse.

### 3.3 El "modo sin backend" giraba temporizadores

Sin `firebase_options.dart`, `FirebaseAuth.instance` lanza. Riverpod 3 reintenta los providers fallidos con backoff, así que la app quedaba reintentando indefinidamente contra un backend inexistente. Ahora `authStateProvider` comprueba `Firebase.apps.isEmpty` y emite "sin sesión", que es la respuesta honesta.

### 3.4 Dos bugs de layout reales

El pie del login desbordaba 71px, y con el texto escalado a 1.5x por accesibilidad se rompía más. Se cambió el `Row` por un `Wrap`. Los detectaron los tests de widget, no una revisión visual.

### 3.5 Los timestamps entraban al dominio en hora local

`Timestamp.toDate()` devuelve hora local mientras el resto del dominio usa UTC. Como las rachas se calculan con fechas, esa mezcla habría dado resultados distintos según el huso del dispositivo. Ahora todo lo que cruza al dominio va en UTC.

---

## 4. Sobre los DTOs escritos a mano

El diseño preveía Freezed + json_serializable para los DTOs. `UserDto` está escrito a mano, y no por comodidad:

- `FieldValue.serverTimestamp()` es un centinela, no un valor: un serializador lo emitiría como objeto vacío.
- Las actualizaciones son **parciales por obligación** —las reglas exigen `onlyFields`—, así que un `toJson()` completo mandaría `aura` y `stats` en cada guardado y Firestore rechazaría la escritura entera.
- `Timestamp` necesita converter propio en ambos sentidos.

El límite arquitectónico se respeta igual: ningún `DocumentSnapshot` sale de la capa de datos. Los DTOs de la Fase 2, que sí son JSON puro, pueden usar codegen sin problema.

---

## 5. Qué quedó construido

```
backend/functions/src/
├── callable/register-profile.ts     transacción de alta + claim (idempotente)
├── callable/set-user-role.ts        rol + auditLog + anti-autobloqueo
├── callable/delete-account.ts       borrado real: Firestore, Storage y Auth
├── triggers/on-user-update.ts       proyección a publicProfiles
└── lib/validation.ts                esquemas zod + handles reservados

packages/ascend_domain/lib/src/usecases/
├── auth_usecases.dart               9 casos de uso de sesión
└── profile_usecases.dart            6 casos de uso de perfil

packages/ascend_data/lib/src/
├── dtos/user_dto.dart               mapeo tolerante a documentos rotos
├── datasources/remote/              Firebase Auth · Firestore
├── repositories/                    AuthRepositoryImpl · UserRepositoryImpl
└── providers/repository_providers.dart   grafo completo de DI

apps/ascend_mobile/lib/features/
├── auth/application/                session.dart · auth_controller.dart
├── auth/presentation/screens/       login · registro · recuperación ·
│                                    verificación · suspendida · completar perfil
└── profile/                         perfil · edición
```

### Decisiones codificadas, no solo escritas

- **`resolveSessionState` es una función pura** con siete estados y su tabla de decisión testeada. El estado de sesión no es un booleano: entre "sin sesión" y "puede usar la app" hay tres situaciones que necesitan pantallas distintas.
- **El claim gana sobre el documento.** `UserDto` acepta el rol del token y descarta el del documento. Hay un test que manipula el documento a `admin` y verifica que el usuario siga siendo común.
- **La recuperación de contraseña nunca revela si un email existe.** El repositorio convierte el fallo en éxito y lo registra internamente; el mensaje es deliberadamente ambiguo.
- **`registerProfile` es idempotente** y hay una pantalla que la reinvoca cuando detecta una cuenta sin perfil.
- **Las validaciones están duplicadas en Dart y en TypeScript** a propósito: una llamable se puede invocar con `curl`. Un test compara el patrón de handle de ambos lados para que no se separen en silencio.

---

## 6. Lo que no entró

- **Onboarding de 4 pasos.** No estaba en los objetivos acordados para esta fase. El estado `needsOnboarding` y su guard quedan implementados: enchufarlo es cambiar una condición en `resolveSessionState`.
- **Google y Apple.** Ver §2.3.
- **Textos en inglés en pantalla.** Las claves ARB están en los dos idiomas y los delegates ya están enchufados al `MaterialApp`, pero las pantallas siguen usando literales en español, igual que el design system de la Fase 0. Migrarlos es mecánico y el roadmap lo ubica en la Fase 9.
- **Verificación end-to-end contra Firebase real.** Imposible hasta que existan los proyectos.

---

## 7. Configuración que depende de vos

1. **Proyectos Firebase** `ascend-dev` / `ascend-stg` / `ascend-prod` + `flutterfire configure`. Es el bloqueante principal: sin `firebase_options.dart` nada de esta fase se puede ejecutar contra el backend real.
2. **Habilitar Email/Password** en Authentication → Sign-in method.
3. **App Check.** Las cuatro llamables tienen `enforceAppCheck: true`, siguiendo el complemento del ADR-002. **Si App Check no está configurado, el registro falla**: hay que registrar la app en App Check (Play Integrity / DeviceCheck / reCAPTCHA) antes de probar en un dispositivo real.
4. **Desplegar reglas, índices y functions:**

   ```bash
   cd backend && firebase deploy --only firestore:rules,firestore:indexes,functions
   ```

5. **Primer administrador.** `setUserRole` exige que quien la llame ya sea admin, así que el primero se asigna una única vez con el Admin SDK:

   ```bash
   node -e "require('firebase-admin').initializeApp();require('firebase-admin').auth().setCustomUserClaims('UID','{\"role\":\"admin\",\"status\":\"active\"}')"
   ```

   Después de eso, todo cambio de rol pasa por la función y queda en `auditLog`.
6. **JDK 21+ permanente** si querés correr los tests de reglas sin preparar el entorno cada vez.
