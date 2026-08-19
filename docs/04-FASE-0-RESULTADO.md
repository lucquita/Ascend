# Fase 0 — Fundaciones · Resultado

**Estado: completada.** Fecha: 2026-08-07.
**Tests de reglas ejecutados contra el emulador y en verde el 2026-08-12** (ver §3.2).
Toolchain verificado: Flutter 3.44.4 · Dart 3.12.2 · Node 24.14 · Firebase CLI 15.21 · JDK 21.0.12.

---

## 1. Verificación de los criterios de aceptación

| Criterio | Estado | Evidencia |
|---|---|---|
| Análisis estático sin issues en todo el monorepo | ✅ | `dart analyze --fatal-infos .` → *No issues found* |
| Tests en verde | ✅ | **117 tests** (39 core · 21 domain · 28 ui · 20 data · 9 mobile) |
| Formato consistente | ✅ | `dart format --set-exit-if-changed .` limpio |
| La app arranca y se navega | ✅ | Smoke tests montan `AscendApp` completa y recorren las 4 secciones |
| Un `throw` NO muestra la pantalla roja | ✅ | Test dedicado + pantalla `/dev-tools` para verificarlo en el dispositivo |
| Panel web compila en release | ✅ | `flutter build web --release` → *Built build\web* |
| Cloud Functions compilan | ✅ | `tsc` sin errores, `strict` + `noUncheckedIndexedAccess` |
| Reglas de Firestore escritas y cerradas | ✅ | `backend/firestore.rules` con denegación por defecto |
| Suite de tests de reglas | ✅ | **46 tests en verde** contra el emulador de Firestore. Ver §3.2 |
| Build de Android / iOS | ⚠️ no verificable acá | Ver §3.1 |

**Total: 117 tests de Dart + 46 tests de reglas = 163 tests pasando, 0 issues de análisis.**

---

## 2. Desviaciones respecto del diseño aprobado

Cuatro cosas cambiaron al chocar con el toolchain real. Ninguna afecta la arquitectura; sí conviene tenerlas registradas.

### 2.1 Sin `riverpod_generator`: providers escritos a mano ⚠️

**Qué decía el diseño:** Riverpod 3 + `riverpod_annotation` con generación de código.

**Qué pasó:** hay una incompatibilidad dura en la cadena de dependencias actual.

```
Flutter 3.44.4  →  fija  meta 1.18.0
analyzer >=13.1 →  exige meta ^1.18.3     ← incompatible
build_runner >=2.15.3 → exige analyzer >=13.3
riverpod_generator    → exige build_runner >=2.15.3
```

Es decir: `build_runner 2.15.1` es la última versión usable con este Flutter, y `riverpod_generator` no funciona con ella.

**Qué se hizo:** los providers se declaran explícitamente (`Provider<T>(...)`, `StreamProvider<T>(...)`). Es más verboso, pero no pierde nada: el tipado, la sustitución en tests y el grafo de dependencias son idénticos. El codegen solo ahorraba escritura.

**Cuándo revisarlo:** en la próxima actualización de Flutter. Está anotado como tope duro en `packages/ascend_domain/pubspec.yaml`. Migrar después no obliga a reescribir nada: `@riverpod` genera exactamente los mismos providers.

**Freezed y json_serializable sí funcionan** con `build_runner 2.15.1`, así que los DTOs de la Fase 2 mantienen su codegen. La única pega es que `freezed` resuelve a `3.2.6-dev.1`, la única versión compatible con `freezed_annotation 3.1.0`. Al ser `dev_dependency`, no entra en el binario que se publica.

### 2.2 Pub workspaces nativo en vez de `melos bootstrap`

Dart 3.12 trae workspaces nativos: un solo `pubspec.lock` y un único `.dart_tool` compartido, resueltos con `flutter pub get` en la raíz. Es más rápido y más confiable que la vinculación por symlinks.

Melos se conserva, pero solo como **orquestador de scripts** (`melos run ci`, `melos run test`). Los desarrolladores ya no necesitan `melos bootstrap`.

### 2.3 Poppins vía `google_fonts` (deuda técnica registrada)

Empaquetar los `.ttf` requiere descargarlos, cosa que no hice sin tu autorización. Hoy la fuente se resuelve con `google_fonts`, que la baja en el primer arranque.

**Por qué importa:** en un arranque en frío sin conexión, la app cae a la fuente del sistema. Es degradación elegante, no un crash, pero no es lo que queremos en producción.

**Acción:** bajar los cuatro pesos de Poppins (Regular, Medium, SemiBold, Bold) a `packages/ascend_ui/assets/fonts/` y descomentar la sección `fonts:` del pubspec. Está anotado en el propio archivo. Cinco minutos de trabajo cuando digas.

### 2.4 `dart format` con el ancho por defecto (80)

El diseño mencionaba 100 columnas. Se usa el default de Dart porque es lo que aplica el formateo automático de VS Code y de Android Studio sin configurar nada: pelearse con la herramienta por 20 columnas genera diffs de ruido en cada PR.

---

## 3. Verificaciones diferidas del entorno

Ninguna es un problema del código; son cosas que faltaban en la máquina.
La §3.2 quedó **resuelta el 2026-08-12**; la §3.1 sigue abierta.

### 3.1 No hay Android SDK instalado

```
[!] No Android SDK found. Try setting the ANDROID_HOME environment variable.
```

`flutter build apk` no corre. El código Dart sí compila —lo demuestran el build web en release y los 117 tests—, pero el empaquetado nativo no se puede probar.

**Para resolverlo:** instalar Android Studio o el command-line tools, y luego:

```bash
flutter doctor --android-licenses
```

El workflow de CI ya compila Android e iOS, así que en cuanto haya repositorio esto queda cubierto de todos modos.

### 3.2 Tests de reglas — ejecutados y en verde ✅

**Resultado del 2026-08-12: 46 tests ejecutados, 46 en verde, 0 fallidos.**

Los 46 casos de `backend/tests/firestore.rules.test.js` (58 aserciones en 9 bloques) cubren cada ataque que las reglas deben frenar: autoasignarse Aura, promoverse a admin, levantar la propia suspensión, leer datos ajenos, publicar logros falsos, dar like en nombre de otro y reportar en bucle.

**Para ejecutarlos:**

```bash
cd backend/tests && npm install && npm test
```

Ese comando levanta el emulador, corre la suite y lo apaga.

#### Requisito de entorno: JDK 21+

El emulador de Firestore corre sobre la JVM y `firebase-tools` 15.x **rechaza cualquier JDK anterior al 21**:

```
Error: firebase-tools no longer supports Java version before 21.
```

Con solo el JRE 8 instalado, el comando muere antes de arrancar el emulador y no ejecuta un solo test. Esto también estaba mal en CI —el job `security-rules` pedía Java 17— y quedó corregido a 21 en `.github/workflows/ci.yaml`. El Java 17 del job de Android **no** se tocó: es el que corresponde a Gradle.

#### Un test que no probaba lo que decía probar

El primer run dio **45/46**. El caso que falló fue `RECHAZA que el cliente se levante una suspensión`, y la causa no estaba en las reglas sino en el test:

```js
// El fixture crea a Alice con status: 'active'…
updateDoc(doc(alice(), 'users/alice'), { status: 'active' });  // …y le escribe el MISMO valor
```

`diff().affectedKeys()` no registra un campo cuyo valor no cambió, así que `onlyFields()` recibía un conjunto vacío y la escritura pasaba. Correctamente: escribir el valor que el documento ya tiene no es una escalada de privilegios. El test afirmaba cubrir un ataque que nunca ejecutaba.

**Corrección:** se agregó al fixture una cuenta realmente suspendida (`users/bob` con `status: 'suspended'`) y el test ahora intenta el ataque de verdad —volver a `active`— más la variante de esconder el campo prohibido entre campos permitidos. Ambas son rechazadas.

Las reglas **no se modificaron**: ya defendían este caso. Se verificó que la denegación proviene de la regla correcta y no del `deny-by-default`, leyendo la traza del emulador:

```
PERMISSION_DENIED: false for 'update' @ L88
```

L88 es el `allow update` de `users/{uid}` — el guard de `onlyFields` + `unchanged`, exactamente la defensa que el test debe ejercitar.

---

## 4. Qué quedó construido

```
Ascend/
├── pubspec.yaml                  workspace nativo con 7 miembros
├── melos.yaml                    scripts: analyze · format · test · gen · ci
├── analysis_options.yaml         lints estrictos compartidos
├── .github/workflows/ci.yaml     4 jobs: dart · reglas · functions · builds
│
├── packages/
│   ├── ascend_core/              Result · Failure (11 tipos) · RetryPolicy ·
│   │                             Validators · AscendDateUtils · IdGenerator
│   ├── ascend_domain/            entidades · 10 enums tolerantes a valores
│   │                             desconocidos · 9 contratos de repositorio
│   ├── ascend_data/              ErrorMapper (40+ códigos de Firebase) ·
│   │                             runGuarded · guardStream · providers de infra
│   ├── ascend_ui/                tokens · temas claro/oscuro · AsyncStateBuilder ·
│   │                             ErrorStateView · EmptyStateView · OfflineBanner ·
│   │                             Skeleton · AuraBadge · ProgressRing · StreakFlame
│   └── ascend_l10n/              ARB es/en, generación verificada
│
├── apps/
│   ├── ascend_mobile/            bootstrap con 4 trampas de error · GoRouter con
│   │                             shell de 4 ramas y guards · pantalla /dev-tools
│   └── ascend_admin/             shell responsive con 10 secciones · guard de rol
│
└── backend/
    ├── firestore.rules           cerradas por defecto, campos protegidos
    ├── storage.rules             evidencias privadas por diseño
    ├── firestore.indexes.json    15 índices + TTL de notificaciones
    ├── firebase.json             emuladores + hosting + functions
    ├── functions/                TypeScript strict, Node 22, healthCheck
    └── tests/                    46 casos de reglas de seguridad (en verde)
```

### Decisiones de diseño que quedaron codificadas, no solo escritas

- **`Failure` es `sealed`** → un `switch` que olvide un caso no compila. El mapeo a mensajes amigables es exhaustivo por construcción.
- **`Mission.canComplete`** vive en el dominio, no en el botón. Impide completar dos veces la misma misión (el exploit más obvio del sistema de Aura) y exige evidencia cuando corresponde.
- **`PostType.requiresSource`** convierte la premisa del producto —el feed solo muestra logros reales— en una regla verificada tanto en el dominio como en las reglas de Firestore.
- **`UserRole.fromWire`** devuelve `user` ante cualquier valor desconocido. Un error de parseo nunca puede conceder permisos de administrador.
- **`Visibility.fromWire`** devuelve `private` ante lo desconocido. En privacidad, el default seguro es el más restrictivo.
- **El token `aura` (`#F59E0B`) reprueba AA como texto**, y hay un test que lo verifica. Si alguien lo cambia por descuido, el build falla.
- **`RetryPolicy` no reintenta fallos no recuperables.** Reintentar un rechazo de permisos solo gasta batería y cuota.
- **`guardStream` emite el fallo sin cerrar la suscripción**, así una pantalla en tiempo real se recupera sola tras un corte de red en vez de quedarse muerta.

---

## 5. Cómo trabajar con esto

```bash
# Poner en marcha el proyecto (una sola vez tras clonar)
flutter pub get
```

```bash
# El pipeline completo, igual que en CI
dart format --set-exit-if-changed . && dart analyze --fatal-infos . && flutter test packages apps
```

```bash
# Correr la app móvil
cd apps/ascend_mobile && flutter run --dart-define=FLAVOR=dev
```

```bash
# Correr el panel de administración
cd apps/ascend_admin && flutter run -d chrome
```

```bash
# Tests de las reglas de seguridad (requiere JDK 21+ en el PATH)
cd backend/tests && npm install && npm test
```

Dentro de la app, el botón **Diagnóstico** (visible fuera de producción) abre `/dev-tools`: ahí se verifican en vivo la red de captura de errores y todos los estados del design system.

---

## 6. Lo que hace falta antes de la Fase 1

Tres cosas dependen de vos, no de mí:

1. **Crear los proyectos Firebase** `ascend-dev`, `ascend-stg` y `ascend-prod`, y correr `flutterfire configure` en cada uno. Hasta que exista `firebase_options.dart`, la app arranca en "modo sin backend" — deliberado, para que la Fase 0 fuera verificable sin depender de la nube.
2. **Decidir si instalás el Android SDK** en esta máquina o si te alcanza con que CI compile los binarios.
3. **Instalar un JDK 21+ de forma permanente** si querés correr los tests de reglas sin preparar el entorno cada vez. La corrida del 2026-08-12 usó un JDK portable en una carpeta temporal de sesión, que no sobrevive al reinicio; en esta máquina el único JDK instalado es el JRE 8, que `firebase-tools` rechaza. En CI ya está resuelto (`setup-java` con 21).

   ```bash
   winget install --id Microsoft.OpenJDK.21 -e
   ```

Con eso resuelto, la Fase 1 (autenticación y perfil) arranca sin bloqueos.
