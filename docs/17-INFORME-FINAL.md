# ASCEND — Informe final

**Fecha:** 2026-08-18.
**Alcance:** fases 0 a 10 del roadmap, ejecutadas con autorización general del
product owner.

---

## 1. Resumen

Ascend es una plataforma de crecimiento personal con **dos aplicaciones reales**
—móvil y panel web de administración— sobre un único Firestore compartido en
tiempo real.

| Métrica | Valor |
|---|---|
| Tests en verde | **813** |
| — Dart | 544 (core 53 · domain 232 · data 114 · ui 28 · móvil 90 · admin 27) |
| — Cloud Functions | 154 |
| — Reglas de Firestore | 115 |
| Issues de `dart analyze --fatal-infos` | 0 |
| Paquetes en el monorepo | 7 |
| Cloud Functions desplegables | 18 |
| APIs externas integradas | 3 (Open-Meteo, Open Library, Gemini) |

---

## 2. Fases completadas

| Fase | Qué entregó | Documento |
|---|---|---|
| 0 | Monorepo, design system, router, red de errores | [04](04-FASE-0-RESULTADO.md) |
| 1 | Autenticación, perfil, roles por custom claim | [05](05-FASE-1-RESULTADO.md) |
| 2A | Objetivos, categorías, hitos, cascada de borrado | [07](07-FASE-2A-RESULTADO.md) |
| 2B | Misiones, presupuesto, pantalla "Hoy" | [08](08-FASE-2B-RESULTADO.md) |
| 3 | Evidencias con cola local | [09](09-FASE-3-RESULTADO.md) |
| 4 | Aura server-authoritative, ledger, rachas | [10](10-FASE-4-RESULTADO.md) |
| 5 | Comunidad: feed, likes, comentarios, reportes | [11](11-FASE-5-RESULTADO.md) |
| 6 | IA con Gemini vía Cloud Function | [12](12-FASE-6-RESULTADO.md) |
| 7 | Open-Meteo y Open Library | [13](13-FASE-7-RESULTADO.md) |
| 8 | Panel de administración funcional | [14](14-FASE-8-RESULTADO.md) |
| 9 | Notificaciones | [15](15-FASE-9-RESULTADO.md) |
| 10 | QA y pre-lanzamiento | [16](16-FASE-10-RESULTADO.md) |

---

## 3. Problemas encontrados y resueltos

### 3.1 Seguridad

| Hallazgo | Fase | Qué pasaba |
|---|---|---|
| Evidencias auto-aprobables | 3 | Las reglas protegían `auraReward` y `ownerId`, pero `evidence` era un mapa libre: cualquiera podía escribir su propia aprobación de moderación, incluso escondiéndola dentro de la escritura que completa la misión |
| Administrador suspendido con poder intacto | 8 | `isAdmin()` solo miraba el rol: suspender a un administrador no le quitaba nada hasta que su token caducara — y la suspensión es justamente la herramienta para frenar a uno que hace daño |
| Escrituras administrativas sin auditoría garantizada | 8 | Las reglas permitían al panel escribir directo, pero `auditLog` es inescribible desde cualquier cliente: siempre existía el caso de la acción aplicada sin rastro de quién la hizo |

Las tres se cerraron con tests de reglas que fijan el comportamiento.

### 3.2 Correctitud

| Hallazgo | Fase | Qué pasaba |
|---|---|---|
| `Stream.empty()` en providers sin sesión | 2A | El stream se cierra sin emitir: la pantalla quedaba en `AsyncLoading` **para siempre**. Es exactamente el modo de fallo que el product owner prohibió |
| Lanzar dentro de `AsyncNotifier.build()` | 5 | Deja el provider colgado en `AsyncLoading`. El feed no cargaba nunca |
| Contador de costos de IA siempre en cero | 8 | La agregación consultaba `aiUsage` por un campo que los documentos no tenían; el panel habría mostrado `$0.00` indefinidamente sin dar señal de error |
| Guardado de preferencias descartado en silencio | 9 | El uid y el perfil venían de dos providers distintos; en un arranque en frío uno no había emitido y el guardado devolvía `false` sin decir nada |

### 3.3 Layout (los tres estaban en el design system)

| Hallazgo | Fase | Síntoma |
|---|---|---|
| `AscendSkeletonList` sin `shrinkWrap` | 8 | *"Vertical viewport was given unbounded height"* al cargar dentro de un scrollable |
| Botones con ancho mínimo infinito | 8 | Cualquier botón dentro de un `Row` rompía el layout; `expanded: false` no servía para nada porque el tema forzaba el ancho igual |
| Controlador destruido antes de tiempo | 8 | Aserción `_dependents.isEmpty` del framework, que aparece un rato después y no señala la causa |

Ninguno se parcheó en el sitio de uso: los tres se corrigieron en `ascend_ui`,
porque el siguiente que los pise no va a saber que ya pasó.

### 3.4 Producto

| Hallazgo | Fase | Qué pasaba |
|---|---|---|
| El botón "+" de la app no hacía nada | 10 | El botón más visible llevaba a un placeholder de la Fase 2 |
| Historial de misiones sin construir | 10 | Un botón que decía "llega con el sistema de Aura", seis fases después de que Aura terminara |
| Semilla de categorías como paso manual | 8 | Sin categorías nadie puede crear un objetivo, y el paso manual no lo corría nadie. Ahora se carga desde el panel |

---

## 4. Lo que queda pendiente

### 4.1 Configuración externa — bloquea la verificación real

Nada de esto es código: son credenciales y permisos que solo el product owner
puede dar.

| # | Qué | Comando o lugar | Qué desbloquea |
|---|---|---|---|
| 1 | Credenciales de Firebase | `flutterfire configure --project=ascend-dev` | **Todo lo que toque el backend real**, incluida la verificación de BUG-001 |
| 2 | Desplegar reglas e índices | `firebase deploy --only firestore:rules,firestore:indexes` | Que las reglas probadas rijan de verdad |
| 3 | Desplegar funciones | `firebase deploy --only functions` | Aura, IA, moderación, métricas, recordatorios |
| 4 | Primer administrador | Ver [14](14-FASE-8-RESULTADO.md) §11 | Entrar al panel |
| 5 | API key de Gemini | `firebase functions:secrets:set GEMINI_API_KEY` | IA real en vez de plantillas |
| 6 | Plan Blaze | Consola de Firebase | Cloud Storage: las fotos de evidencia |
| 7 | Clave APNs | Consola de Firebase | Push en iOS |

Los pasos 5, 6 y 7 **no rompen nada si no se hacen**: la IA cae a plantillas por
categoría, las fotos quedan en cola con un mensaje honesto, y las notificaciones
siguen llegando a la bandeja in-app. Es deliberado — cada integración que puede
faltar está detrás de un puerto que degrada.

El paso 1 sí es bloqueante para cualquier prueba contra Firebase real.

### 4.2 Trabajo de lanzamiento que no se hizo

Requiere dispositivos, tiendas y un entorno que esta máquina no tiene:

- Tests E2E con Patrol de los cinco flujos críticos.
- Auditoría de performance (arranque, jank, tamaño del APK).
- Build de release firmado, App Bundle, TestFlight, Firebase Hosting.
- Accesibilidad verificada con TalkBack y VoiceOver.
- Política de privacidad, términos y assets de tienda.

### 4.3 BUG-001

**Sigue abierto.** La corrección está aplicada y probada a nivel de código, pero
cerrarlo exige registrar una cuenta real contra `ascend-dev`. Ver
[06-BUGS-CONOCIDOS.md](06-BUGS-CONOCIDOS.md).

---

## 5. Cómo correr el proyecto

### Requisitos

- Flutter (la versión fijada en `pubspec.yaml`), Node 20+, JDK 21 (solo para los
  tests de reglas).

### Primera vez

```bash
flutter pub get
```

```bash
npm install --prefix backend/functions
```

### Aplicación móvil

```bash
flutter run -d <dispositivo> --dart-define=FLAVOR=dev
```

Sin `firebase_options.dart` arranca en **modo sin backend**: la navegación, los
temas y los estados de error se pueden recorrer enteros.

### Panel de administración

```bash
flutter run -d chrome --dart-define=FLAVOR=dev
```

(desde `apps/ascend_admin`)

### Tests

```bash
flutter test
```

```bash
npm test --prefix backend/functions
```

Los de reglas necesitan el emulador de Firestore y por lo tanto un JDK 21. La
receta para esta PC concreta está en la memoria del proyecto.

---

## 6. Cómo demostrarlo

Guion de unos diez minutos, en orden, que toca todos los requisitos académicos.

1. **Panel → Categorías → "Cargar catálogo inicial".** Deja el catálogo listo y
   muestra la escritura administrativa.
2. **Móvil → crear una cuenta.** Muestra registro, validación y verificación.
3. **Móvil → crear un objetivo con el asistente de IA.** Muestra la integración
   con Gemini —o las plantillas, si la key no está— y la creación transaccional
   de objetivo con sus misiones.
4. **Móvil → completar una misión.** El Aura aparece en unos segundos: la calcula
   el servidor, no el cliente. Es el momento para mostrar el ledger en la
   pantalla de Aura.
5. **Móvil → misión de fitness con fecha próxima.** Aparece el aviso de clima:
   Open-Meteo, sin API key.
6. **Móvil → publicar el logro en la comunidad.** Con dos cuentas se ve el like y
   el comentario en tiempo real.
7. **Móvil → reportar la publicación desde la segunda cuenta.**
8. **Panel → Reportes.** El reporte ya está ahí, sin recargar: es el mismo
   Firestore en tiempo real. Resolverlo.
9. **Panel → Auditoría.** La acción quedó registrada con quién, cuándo y por qué.
10. **Panel → Usuarios → dar rol de administrador.** Y mostrar que no se puede
    hacer sobre uno mismo.

El punto 8 es el que demuestra el requisito central —dos aplicaciones sobre un
Firestore compartido en tiempo real— y conviene no apurarlo.

### Qué mostrar si algo falla en vivo

Está previsto: cortar la conexión muestra el `OfflineBanner` y la app sigue
funcionando con la caché de Firestore. Es una demostración en sí misma, no un
accidente.

---

## 7. Estado final

| | Estado |
|---|---|
| Aplicación móvil | Completa para el alcance del MVP |
| Panel de administración | 5 de 10 secciones funcionales; el resto marcado en el menú |
| Firestore | Reglas cerradas y probadas, índices al día — **sin desplegar** |
| Cloud Functions | 18 escritas y probadas — **sin desplegar** |
| Requisitos académicos | Todos cumplidos a nivel de código (ver [16](16-FASE-10-RESULTADO.md) §6) |
| Verificación contra Firebase real | **Pendiente**, bloqueada por el paso 1 de §4.1 |
