# Fase 8 — Panel de administración · Resultado

**Estado: completada.** El panel dejó de ser una maqueta: entra con una cuenta
real, lee datos reales y sus acciones quedan auditadas.
Fecha: 2026-08-17.

---

## 1. Verificación

| Comprobación | Estado | Evidencia |
|---|---|---|
| Formato | ✅ | `dart format --set-exit-if-changed .` → 0 cambios |
| Análisis estático | ✅ | `dart analyze --fatal-infos .` → *No issues found* |
| Tests de Dart | ✅ | **472** (+68) |
| Tests de Functions | ✅ | **118** (+28) |
| Tests de reglas | ✅ | **115** (+12) |
| Lint + `tsc` | ✅ | limpios |

**Total: 705 tests en verde.** Desde 597 en la Fase 7, se agregaron **108**.

Desglose de los 472 de Dart: core 49 · domain 197 · data 109 · ui 28 · móvil 62
· **admin 27** (antes no tenía ninguno).

---

## 2. De qué se partía

El panel existía desde la Fase 0 como esqueleto navegable, y esa era su
función. Pero al llegar acá el estado era:

```dart
// apps/ascend_admin/lib/router/admin_router.dart — ANTES
final Provider<UserRole?> adminSessionRoleProvider = Provider<UserRole?>(
  (ref) => UserRole.admin,   // ← siempre administrador
);
```

- `Firebase.initializeApp()` **no se llamaba en ninguna parte**: la app web
  arrancaba sin backend.
- El rol estaba fijo en `admin`, así que cualquiera que abriera la URL entraba.
- Las diez secciones eran el mismo placeholder.

Era, en los hechos, **una sola aplicación y una maqueta**. El requisito
académico pide dos aplicaciones reales compartiendo Firestore, así que esto era
el incumplimiento más caro que quedaba.

---

## 3. Qué quedó construido

```
apps/ascend_admin/lib/
├── bootstrap.dart                        arranque + Firebase + red de errores
├── router/admin_router.dart              guard real por claim de rol
├── shared/admin_widgets.dart             encabezado, tarjeta, insignia, tabla
└── features/
    ├── auth/         AdminSessionState · AdminAuthController · login
    ├── dashboard/    KPIs desde un único documento agregado
    ├── users/        tabla con búsqueda, filtros, paginación, CSV y acciones
    ├── moderation/   bandeja priorizada por gravedad
    ├── catalog/      alta/edición de categorías + carga de la semilla
    └── audit/        registro inmutable de acciones administrativas

backend/functions/src/
├── lib/admin-guard.ts                    requireAdmin (rol + cuenta activa)
├── lib/firestore-values.ts               lectura defensiva de documentos
├── services/admin-service.ts             decisiones puras de moderación
├── callable/set-user-status.ts           suspender / reactivar + auditoría
├── callable/moderate-content.ts          resolver reporte + ocultar + auditoría
└── scheduled/aggregate-stats.ts          métricas diarias del dashboard

packages/ascend_domain/…/admin_usecases.dart   AdminStats · AuditEntry ·
                                               filtros · cola · casos de uso
packages/ascend_data/…/admin_repository_impl.dart
packages/ascend_core/…/utils/csv.dart          exportación con escapes
```

Cinco de las diez secciones ya funcionan (dashboard, usuarios, reportes,
categorías, auditoría). Las otras cinco siguen siendo placeholders, y el menú
**las marca con un reloj** en vez de dejar que alguien lo descubra recién al
hacer clic.

---

## 4. Las decisiones que importan

### 4.1 El guard del router NO es la seguridad

Es la línea que ordena toda la fase. `adminSessionProvider` decide qué pantalla
mostrar; **las reglas de Firestore deciden qué datos salen**. Un cliente
manipulado que saltee el guard llega a un panel que no puede leer un solo
documento, y hay tests de reglas que lo fijan:

```
una cuenta común no puede listar los usuarios          → assertFails
una cuenta común no lee las métricas agregadas         → assertFails
una cuenta común no ve la cola de moderación           → assertFails
una cuenta común no lee el registro de auditoría       → assertFails
un anónimo no toca nada del panel                      → assertFails
```

El rol se lee del **custom claim del token**, nunca de un campo de Firestore
(ADR-004). El campo `users/{uid}.role` se mantiene como espejo de solo lectura
para poder listar y filtrar sin inspeccionar tokens, pero la autoridad es el
claim.

### 4.2 Toda escritura administrativa pasa por Cloud Functions

Las reglas le permitirían al administrador actualizar un reporte y ocultar una
publicación directamente desde el panel. Aun así no se hace, porque `auditLog`
es **inescribible desde cualquier cliente** y el requisito es que toda acción
quede registrada.

Con dos escrituras separadas —una del panel, otra del servidor— siempre existe
el caso en que la primera funciona y la segunda no: queda una publicación oculta
sin rastro de quién la ocultó. En `moderateContent` las tres escrituras
—reporte, contenido y auditoría— van en un solo `batch`: o quedan las tres o no
queda ninguna.

La única excepción es el catálogo de categorías, que se escribe directo: no hay
nada que auditar más allá del propio documento.

### 4.3 El dashboard no recorre colecciones

Un `count()` sobre `users` se factura a una lectura por cada mil documentos, y
se repetiría **cada vez que alguien abre el panel**. Con diez administradores
mirándolo varias veces al día, contar en vivo es una factura por mirar un número
que casi no cambia.

`aggregateStats` corre a las 04:00 UTC, escribe `adminStats/{fecha}` y una copia
en `adminStats/latest`, y el panel lee **un solo documento**. Es el criterio de
aceptación de la fase, y de paso deja la serie histórica sin recalcular nada.

El documento lleva sellada la hora de cálculo, y el panel avisa cuando pasan más
de 48 horas: mostrar números de hace una semana como si fueran de hoy es peor
que no mostrar nada, porque alguien decide con ellos.

### 4.4 La bandeja de moderación se ordena por gravedad, no por fecha

`sortModerationQueue` ordena primero por gravedad del motivo y, a igual
gravedad, **primero lo más viejo**. Una bandeja cronológica hace que un caso de
violencia espere detrás de veinte reportes de spam; y con lo más nuevo primero,
los reportes de una racha activa empujarían los viejos hacia abajo para siempre.

### 4.5 Suspender exige un motivo escrito

Es la acción más grave del panel y la más difícil de revertir socialmente: quien
la sufre pregunta por qué. Sin nota, un mes después ni quien la aplicó puede
explicarlo, y la única salida es levantarla a ciegas. Se valida en el caso de
uso, en la UI y otra vez en la Cloud Function.

Nadie puede tocarse a sí mismo —ni el rol ni el estado—: quitarse el admin un
viernes deja el panel sin quien lo administre, y recuperarlo exigiría un script
con credenciales de servicio.

### 4.6 La búsqueda es local, y se dice

Firestore no sabe buscar subcadenas —solo prefijos exactos sobre un campo
indexado—, así que buscar "pérez" en toda la colección exigiría un motor de
búsqueda entero. Para un panel que pagina de a 25, filtrar en memoria alcanza.

Queda anotado como límite conocido, y **la pantalla lo dice**: cuando no hay
coincidencias, el mensaje aclara que la búsqueda alcanza a las cuentas ya
cargadas.

### 4.7 La exportación CSV escapa de verdad

`toCsv` vive en `ascend_core` y está probado aparte, porque la parte difícil de
un CSV no es generarlo sino escaparlo: un escape mal hecho no falla, produce un
archivo que abre igual y tiene los datos corridos de columna. Cubre comas,
comillas, saltos de línea, filas cortas, fechas ISO y **inyección de fórmulas**
(una celda que empieza con `=` la ejecuta Excel al abrir el archivo, y en una
exportación de usuarios ese texto lo escribió alguien de afuera).

Se copia al portapapeles en lugar de descargar un archivo: bajar un archivo
desde Flutter Web exige código específico de web —una dependencia o una
compilación condicional— y el CSV termina igual pegado en una hoja de cálculo.
Anotado para la Fase 10.

---

## 5. Agujeros de seguridad encontrados y cerrados

### 5.1 Un administrador suspendido conservaba todo su poder

`isAdmin()` solo miraba el claim `role`. Suspender a un administrador **no le
quitaba nada**: seguía leyendo todos los datos, moderando y editando el catálogo
hasta que su token caducara por su cuenta.

La suspensión es precisamente la herramienta para frenar a un administrador que
está haciendo daño, así que no puede depender de que la persona coopere. Se
cerró en los dos lados:

```
// firestore.rules
function isAdmin() {
  return isSignedIn() && request.auth.token.role == 'admin' && isActive();
}
```

```ts
// lib/admin-guard.ts
const suspended = request.auth.token.status === 'suspended';
if (request.auth.token.role !== 'admin' || suspended) { … }
```

Con cuatro tests de reglas y uno de Functions que fijan el comportamiento. Los
103 tests de reglas anteriores siguen pasando: la regla se endureció, no cambió
de forma.

### 5.2 El contador de costos de IA habría dado cero para siempre

`aggregateStats` consultaba `aiUsage` por un campo `date` que **los documentos
no tenían**: el día vivía solo en el id del documento, y en una consulta por
`collectionGroup` el id no se puede filtrar de forma razonable. El panel de
costos habría mostrado `$0.00` indefinidamente sin dar ninguna señal de error.

Se agregó el campo `date` a la escritura y la agregación pasó a **sumar** el
contador `generations` en vez de contar documentos: cada documento es una
persona-día, así que contarlos daba "cuánta gente usó la IA", que es otra
métrica.

---

## 6. Bugs de layout encontrados (y por qué importan)

Los tres estaban en el design system y afectaban también a la app móvil.

| Bug | Síntoma | Causa |
|---|---|---|
| `AscendSkeletonList` sin `shrinkWrap` | *"Vertical viewport was given unbounded height"* al cargar | Un `ListView` con `NeverScrollableScrollPhysics` dentro de otro scrollable |
| Botones con ancho mínimo infinito | *"BoxConstraints forces an infinite width"* con cualquier botón dentro de un `Row` | `minimumSize: Size.fromHeight(52)` equivale a `Size(double.infinity, 52)` |
| Controlador destruido antes de tiempo | Aserción `_dependents.isEmpty` del framework, un rato después y sin señalar la causa | `showDialog(...).whenComplete(controller.dispose)` destruye el controlador mientras el `TextField` sigue vivo en la animación de salida |

El segundo hacía que `AscendButton(expanded: false)` **no sirviera para nada**:
el tema forzaba el ancho completo igual. Ahora el alto mínimo lo pone el tema y
el ancho lo decide `expanded`, que es donde corresponde.

Ninguno se arregló en el sitio de uso: los tres estaban en `ascend_ui` y se
corrigieron ahí, porque el siguiente que los pise no va a saber que ya pasó.

---

## 7. Código que se compartió en vez de duplicarse

| Qué | De dónde a dónde | Por qué |
|---|---|---|
| `AppFlavor` | `ascend_mobile` → `ascend_core` | El panel apunta al mismo proyecto y necesita el mismo flavor |
| `FirebaseConfig` | `ascend_mobile` → `ascend_data` | Mismo arranque, mismo App Check, mismo modo degradado |
| Red de captura de errores | `bootstrap.dart` → `ascend_ui` | Una red de seguridad copiada se desincroniza: la segunda copia se queda sin la trampa que se agregó en la primera |
| `asString`/`asInt`/`asMap` | `triggers/community.ts` → `lib/firestore-values.ts` | Tercera copia inminente |
| `requireAdmin` | inline → `lib/admin-guard.ts` | Un guard copiado es un guard que alguna vez se copia mal |

El panel comparte además **todo** el design system, el dominio y la capa de
datos: no hay una sola entidad ni un solo repositorio duplicado entre las dos
aplicaciones.

---

## 8. La semilla de categorías dejó de ser un paso manual

Estaba pendiente desde la Fase 2 como "cargar las categorías a mano en la
consola de Firebase". Un paso manual que nadie corre es una app que no se puede
usar: sin categorías, nadie puede crear un objetivo.

Ahora la pantalla de catálogo, cuando está vacía, ofrece **"Cargar catálogo
inicial"** con las diez categorías documentadas en `01-MODELO-DATOS.md`. La
operación pasa por las mismas reglas que cualquier otra escritura del catálogo.

Las categorías no se borran, se desactivan: borrar una con objetivos apuntando a
ella los dejaría huérfanos. El identificador tampoco se puede editar, porque
queda desnormalizado en cada objetivo y cada misión.

---

## 9. Tests agregados (108)

| Suite | Cuántos | Qué fijan |
|---|---|---|
| `ascend_core/csv_test.dart` | 10 | Escapes: comas, comillas dobles, saltos de línea, filas cortas, fechas ISO, `null`, separador alternativo e inyección de fórmulas |
| `ascend_domain/admin_usecases_test.dart` | 31 | Filtros combinados con Y, uid exacto, orden de la cola, no tocarse a uno mismo, motivo obligatorio, métricas viejas, exportaciones |
| `ascend_admin/admin_session_test.dart` | 7 | La tabla de decisión del guard: error → afuera, suspendido → afuera aunque sea admin, valor resuelto nunca queda en "no se sabe" |
| `ascend_admin/admin_screens_test.dart` | 20 | KPIs, aviso de métricas viejas, filtros, confirmaciones, motivo obligatorio, cola priorizada, estados vacíos |
| `functions/admin-service.test.ts` | 28 | Doble resolución, tipo desconocido, nota obligatoria, ventanas UTC, costo estimado, esquemas de entrada, `requireAdmin` |
| `rules` | 12 | Que una cuenta común no lea **nada** del panel, que nadie escriba las métricas, y que un admin suspendido pierda el acceso |

---

## 10. Lo que esta fase deliberadamente no hizo

- **Cinco de las diez secciones siguen en placeholder** (objetivos, plantillas de
  misiones, publicaciones, analíticas, configuración). Se priorizaron las cinco
  que cierran el requisito académico y el criterio de aceptación: rol real,
  datos reales, moderación y auditoría. El menú marca cuáles faltan.
- **No hay notificaciones masivas segmentadas**: dependen de FCM, que es la
  Fase 9.
- **No se despliega nada.** El panel corre con `flutter run -d chrome`; el
  despliegue en Firebase Hosting es de la Fase 10.

---

## 11. Estado tras la fase

| | Estado |
|---|---|
| Móvil | Completa para el alcance del MVP |
| Admin | **Funcional**: login real, guard por claim, 5 secciones con datos |
| Firebase | Reglas endurecidas, índices al día, 3 funciones nuevas; falta desplegar |
| Pendiente externo | API key de Gemini · Cloud Storage (Blaze) · verificación de BUG-001 · **crear el primer administrador** |

### Cómo crear el primer administrador

`setUserRole` exige ser administrador, así que el primero no puede salir del
panel. Se hace una sola vez desde la consola de Firebase o con el Admin SDK:

```bash
firebase functions:shell
```

```js
// dentro del shell, con el Admin SDK ya inicializado
require('firebase-admin').auth().setCustomUserClaims('<uid>', { role: 'admin', status: 'active' })
```

Después de eso, esa cuenta puede dar el rol a las demás desde el panel, y cada
cambio queda en `auditLog`.

Siguiente: **Fase 9 — Notificaciones y pulido**.
