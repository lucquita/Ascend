# Cómo ver la app sin tener nada configurado

> Respuesta corta: **no hace falta ninguno de los ocho pasos de configuración**.
> Con los emuladores locales de Firebase la aplicación funciona entera —
> registrarse, crear objetivos, completar misiones, publicar, moderar desde el
> panel— sin cuenta de Firebase, sin desplegar nada y sin plan de pago.

---

## Por qué el registro se quedaba cargando

Sin `firebase_options.dart`, `Firebase.initializeApp()` falla y la app arranca
en modo sin backend. Hasta ahí, previsto. Lo que **no** estaba previsto es lo
que pasaba al apretar «Registrarme»:

1. El controlador se ponía en `AsyncLoading` y el botón empezaba a girar.
2. Llamaba a `ref.read(signUpWithEmailUseCaseProvider)`, que levanta la cadena
   de dependencias hasta `FirebaseAuth.instance`.
3. Sin Firebase inicializado, eso **lanza** `[core/no-app]`.
4. La excepción escapaba del `await` sin que nadie la atrapara, y el estado
   nunca salía de `AsyncLoading`. **El botón giraba para siempre.**

La grieta estaba entre el controlador y el repositorio: `runGuarded` blinda lo
que pasa *dentro* del repositorio, pero **construirlo** quedaba afuera.

Se cerró con `guardResult`, que envuelve la acción entera —lectura de providers
incluida— en los 22 puntos donde un controlador se pone en carga. Ahora ese caso
muestra el error en pantalla en vez de girar. Hay cinco tests que lo fijan, y el
último comprueba la propiedad que importa: el futuro **siempre completa**.

---

## Requisito único: JDK 21

El emulador de Firestore corre sobre Java y **exige la versión 21 o superior**.
Con Java 17 falla con este mensaje:

```
firebase-tools no longer supports Java version before 21.
```

En Windows, con permisos de administrador:

```bash
winget install Microsoft.OpenJDK.21
```

Si `winget` no funciona, sirve el ZIP portátil de
`https://aka.ms/download-jdk/microsoft-jdk-21-windows-x64.zip`: se descomprime y
se apunta `JAVA_HOME` a esa carpeta.

Es la única instalación que hace falta. No requiere cuenta de Firebase.

---

## Los dos pasos

### 1. Levantar los emuladores

```bash
npx --yes firebase-tools emulators:start --project=demo-ascend
```

Se corre **desde `backend/`**. El prefijo `demo-` del proyecto no es
decorativo: los emuladores reconocen esos identificadores y no piden
credenciales reales ni contactan a ningún servidor.

Queda una consola web en `http://127.0.0.1:4000` donde se ven las cuentas
creadas y los documentos de Firestore en vivo — muy útil para la defensa.

Si además querés las Cloud Functions (Aura, moderación, métricas), antes:

```bash
npm run build --prefix backend/functions
```

### 2. Arrancar la app apuntando ahí

Desde VS Code: **F5** y elegir *«Ascend móvil · emuladores (recomendado)»*. Las
configuraciones están en `.vscode/launch.json`.

Desde la terminal es lo mismo:

```bash
flutter run --dart-define=FLAVOR=dev --dart-define=USE_EMULATORS=true
```

Para el panel, *«Panel admin · emuladores (Chrome)»*.

**Desde el emulador de Android** hay que usar la configuración que pasa
`EMULATOR_HOST=10.0.2.2`: dentro de ese teléfono virtual, `127.0.0.1` es el
propio teléfono, no tu computadora.

---

## Qué funciona y qué no con emuladores

| | Estado |
|---|---|
| Registro, login, perfil | ✅ |
| Objetivos, misiones, «Hoy», historial | ✅ |
| Comunidad: feed, likes, comentarios, reportes | ✅ |
| Panel: usuarios, moderación, categorías, auditoría | ✅ |
| Aura, métricas del dashboard | ✅ con el emulador de funciones |
| Clima y libros (Open-Meteo, Open Library) | ✅ salen a internet de verdad |
| Asistente de IA | 🔸 cae a plantillas: Gemini necesita clave real |
| Fotos de evidencia | 🔸 quedan en cola: el emulador de Storage no reemplaza a Blaze |
| Notificaciones push | 🔸 la bandeja sí, las push del sistema no |

Para crear un administrador y entrar al panel, en la consola del emulador
(`http://127.0.0.1:4000/auth`) se puede editar la cuenta, pero el rol vive en un
*custom claim*. La forma directa es con el shell de funciones apuntado al
emulador, o crear la cuenta y asignarle el claim desde ahí.

---

## Y si preferís ir contra Firebase real

Es el paso 1 del informe final:

```bash
flutterfire configure --project=ascend-dev
```

Con eso solo ya se puede registrar y usar todo lo que escribe directo en
Firestore. Aura, IA y moderación necesitan además desplegar las funciones
(pasos 2 y 3). Ver [17-INFORME-FINAL.md](17-INFORME-FINAL.md) §4.1.
