# ASCEND — Registro de bugs conocidos

> Un bug que no está escrito no existe, y el que no existe no se arregla.
> Cada entrada tiene: síntoma observable, alcance, hipótesis ordenadas por
> probabilidad, y el experimento concreto que confirma o descarta cada una.

| ID | Título | Severidad | Estado | Bloquea |
|----|--------|-----------|--------|---------|
| [BUG-001](#bug-001) | El registro contra Firebase real queda cargando y no completa | Alta | 🟡 Corregido, sin verificar contra Firebase real | Verificación E2E · demo en vivo |

---

## BUG-001 — El registro contra Firebase real queda cargando y no completa {#bug-001}

**Reportado por:** product owner, probando contra el proyecto `ascend-dev`.
**Fecha de registro:** 2026-08-14.
**Severidad:** Alta — impide dar de alta cuentas nuevas contra el backend real.
**Estado:** 🟡 Corrección de H1 aplicada el 2026-08-14. **Falta verificar contra
`ascend-dev`**, cosa imposible desde esta PC hasta que exista
`firebase_options.dart` (ver §"Verificación pendiente").

### Síntoma observado

1. La persona completa el formulario de registro y confirma.
2. La interfaz queda en estado de carga.
3. La operación no completa.
4. No aparece un resultado claro: ni éxito ni un mensaje de error.

### Por qué no se detectó antes

Los tests de la Fase 1 sustituyen el repositorio con dobles
(`overrideWithValue`) y los de reglas corren contra el emulador. **Ningún test
del repositorio ejercita el camino real cliente → Cloud Function → Firestore.**
Es exactamente la clase de fallo que solo aparece integrando de verdad.

### Alcance del código involucrado

La secuencia completa de `AuthRepositoryImpl.signUpWithEmail`
(`packages/ascend_data/lib/src/repositories/auth_repository_impl.dart:113`):

```
1. _auth.createUser(...)          → crea la cuenta en Firebase Auth
2. _auth.registerProfile(...)     → llamable 'registerProfile'  ← sospechoso principal
3. _auth.refreshToken()           → getIdToken(true)
4. _auth.sendEmailVerification()  → envuelto en try/catch, no bloquea
5. _composeUser(fbUser)           → lee users/{uid} de Firestore
```

### Hipótesis, ordenadas por probabilidad

#### H1 — App Check está declarado pero nunca se activa ⭐ principal

Las **cuatro** llamables se despliegan con `enforceAppCheck: true`:

| Función | Archivo |
|---|---|
| `registerProfile` | `backend/functions/src/callable/register-profile.ts:32` |
| `setUserRole` | `backend/functions/src/callable/set-user-role.ts:30` |
| `deleteAccount` | `backend/functions/src/callable/delete-account.ts:32` |
| `healthCheck` | `backend/functions/src/callable/health-check.ts:19` |

`firebase_app_check: ^0.4.6` figura como dependencia en
`packages/ascend_data/pubspec.yaml:27`, pero **no hay una sola línea de Dart que
lo importe ni que llame a `FirebaseAppCheck.instance.activate(...)`**
(verificado por búsqueda en todo el repositorio). Es decir: el paquete está
instalado y jamás se inicializa.

Consecuencia: el cliente invoca la llamable sin token de App Check y el gate la
rechaza antes de ejecutar una sola línea de la función.

Esto ya estaba anticipado por escrito en
[05-FASE-1-RESULTADO.md](05-FASE-1-RESULTADO.md) §7.3:

> **Si App Check no está configurado, el registro falla.**

**Cómo confirmarlo:** en la consola de Firebase → Functions → Registros, buscar
la invocación. Si el gate rechazó, la función **no aparece ejecutándose** y el
cliente recibe `unauthenticated`.

**Corrección aplicada (2026-08-14).** Se activa App Check en el arranque, con
proveedor de depuración fuera de release. Se descartó explícitamente aflojar
`enforceAppCheck`: sería debilitar la seguridad para tapar un problema de
configuración.

| Archivo | Qué cambió |
|---|---|
| `packages/ascend_data/lib/src/config/app_check_service.dart` | Nuevo. Activa App Check; nunca lanza; expone `isActive` |
| `packages/ascend_data/lib/ascend_data.dart` | Exporta el servicio |
| `apps/ascend_mobile/lib/config/firebase_config.dart` | Lo invoca justo después de `Firebase.initializeApp()` |
| `packages/ascend_data/test/app_check_service_test.dart` | Nuevo. 3 tests que blindan el contrato de resiliencia |

Se usan las clases `providerAndroid` / `providerApple` / `providerWeb` y no los
parámetros `androidProvider` / `appleProvider`: estos están deprecados en
`firebase_app_check` 0.4.6 y el proyecto analiza con `--fatal-infos`, así que
usarlos habría roto CI.

Los tests nuevos **no** verifican que la atestación funcione —eso exige un
dispositivo y un proyecto real—. Verifican lo que sí se puede blindar: que la
activación exista, que no tumbe el arranque cuando falla, y que su estado sea
consultable. El modo de fallo original fue "declarado y olvidado"; ahora hay un
test que se rompe si alguien lo desconecta.

#### H2 — El estado de carga sobrevive a la redirección del router

`createUser` (paso 1) crea la cuenta **antes** de que exista el perfil. Eso hace
emitir a `authStateChanges`, y `resolveSessionState` devuelve `needsProfile`
(`apps/ascend_mobile/lib/features/auth/application/session.dart:59`), con lo que
el guard redirige a `/complete-profile` **mientras los pasos 2 a 5 siguen en
vuelo**.

La pantalla de registro se desmonta a mitad de la operación. Si el paso 2 falla
después, el `AsyncError` se escribe sobre un controlador cuya pantalla ya no
está a la vista: **el error existe pero nadie lo pinta**. Encaja con precisión
con "no aparece un resultado claro".

Esta hipótesis es **compatible** con H1 y probablemente actúen juntas: H1 causa
el fallo, H2 lo vuelve invisible.

#### H3 — Desajuste de región

Cliente y servidor están fijados a `southamerica-east1`
(`infrastructure_providers.dart:49` y `constants.ts:8`), así que **coinciden en
el código**. Pero si las functions no se desplegaron, o se desplegaron en otra
región, la llamada da `not-found`. Verificar que
`firebase deploy --only functions` se haya corrido contra `ascend-dev`.

#### H4 — Espera de 60 s del SDK de llamables

`httpsCallable().call()` tiene un timeout por defecto del orden del minuto. Si
la petición se queda sin respuesta, la interfaz se ve "cargando" un rato largo
antes de fallar. Explicaría la percepción de "colgado" sin ser la causa raíz.

#### H5 — Email/Password sin habilitar

Daría `operation-not-allowed` en el paso 1, un fallo rápido y con mensaje. No
encaja bien con el síntoma, pero se descarta en diez segundos mirando
Authentication → Sign-in method.

### Plan de diagnóstico

Ordenado por costo: lo barato primero.

1. Consola de Firebase → Functions → Registros. ¿Llegó a ejecutarse
   `registerProfile`? Si no, es H1 o H3.
2. Verificar que las functions estén desplegadas y en `southamerica-east1`.
3. Verificar Authentication → Sign-in method → Email/Password habilitado.
4. Correr la app con logs a la vista y capturar el `code` exacto de la
   `FirebaseFunctionsException`. El `ErrorMapper` ya lo traduce, pero el código
   crudo es lo que identifica la causa.
5. Comprobar si la cuenta **sí** se creó en Authentication aunque el perfil no.
   Si es así, confirma que el corte está en el paso 2 y que la pantalla
   `/complete-profile` es el camino de recuperación previsto.

### Verificación pendiente

La corrección **no se pudo probar contra Firebase real** desde esta PC: falta
`firebase_options.dart` (está gitignorado, así que no viajó con la carpeta) y
falta el JDK 21 que necesita el emulador. Pasos para cerrar el bug:

1. `flutterfire configure` contra `ascend-dev` en esta máquina.
2. **Registrar la app en App Check** (Firebase Console → App Check → Apps).
3. Correr la app en modo depuración y buscar en el log la línea
   `Enter this debug secret into the allow list…`. Pegar ese token en
   **App Check → Apps → (tu app) → Administrar tokens de depuración**.
   Sin este paso el dispositivo sigue siendo rechazado aunque el código esté
   bien: el token de depuración se autoriza a mano, uno por dispositivo.
4. Verificar que las functions estén desplegadas en `southamerica-east1`
   (descarta H3).
5. Registrar una cuenta nueva de punta a punta.

Recién con el paso 5 en verde el bug pasa a 🟢 cerrado.

### Nota de diseño

El sistema ya está preparado para este fallo: `registerProfile` es idempotente y
existe una pantalla de recuperación (`SessionState.needsProfile` →
`/complete-profile`) que reinvoca la función. O sea, el bug **no deja cuentas
inutilizables**. Lo que falla es la experiencia, no la integridad de los datos.

### Impacto sobre la Fase 2 (Objetivos)

**No la bloquea.** Objetivos escribe directo en Firestore
(`users/{uid}/goals/{goalId}`) sin pasar por ninguna llamable, así que no toca el
camino roto. Sí bloquea la **verificación end-to-end con cuentas nuevas** y la
demostración en vivo, porque no habría forma de registrar a alguien delante de
la clase. Con una cuenta ya creada, el resto del producto se puede probar.

### Estado al cierre de la Fase 10 (2026-08-18)

**Sigue abierto.** La corrección de H1 no se tocó desde que se aplicó, y hay un
test que fija que `AppCheckService.activate()` se llama y que su fallo no aborta
el arranque. Pero **eso no cierra el bug**: lo que hay que comprobar es que una
cuenta nueva se registra contra `ascend-dev`, y para eso hace falta
`firebase_options.dart`, que sigue sin existir en esta máquina.

Lo único que cambió es que ahora el camino tiene más usuarios: las cuatro
llamables originales pasaron a siete (`setUserStatus`, `moderateContent` y las
programadas). Todas se apoyan en el mismo App Check, así que la verificación
sirve para todas a la vez.

**El paso que falta es uno solo:**

```bash
flutterfire configure --project=ascend-dev
```

y después registrar una cuenta desde la app. Si completa, el bug se cierra; si
no, el §"Plan de diagnóstico" de arriba sigue vigente y H2 es la siguiente
hipótesis a probar.
