# Fase 10 — QA y pre-lanzamiento · Resultado

**Estado: completada.**
Fecha: 2026-08-18.

---

## 1. Verificación

| Comprobación | Estado | Evidencia |
|---|---|---|
| Formato | ✅ | `dart format --set-exit-if-changed .` → 0 cambios |
| Análisis estático | ✅ | `dart analyze --fatal-infos .` → *No issues found* |
| Tests de Dart | ✅ | **539** (+9) |
| Tests de Functions | ✅ | 154 |
| Tests de reglas | ✅ | 115 |
| Lint + `tsc` | ✅ | limpios |

**Total: 808 tests en verde.**

---

## 2. Qué busca un barrido de QA

No funcionalidad nueva: **lo que quedó a medias sin que nadie lo notara**. En un
proyecto que avanzó diez fases, eso es siempre lo mismo — botones que llevan a
un cartel de "llega en la Fase N" para una fase que ya terminó, y deuda técnica
que se toleró tres veces porque cada vez costaba menos aguantarla que arreglarla.

| Qué se buscó | Resultado |
|---|---|
| `catch` vacíos | ninguno |
| `TODO` / `FIXME` / `HACK` | ninguno |
| `print()` / `console.log` | ninguno (solo en archivos generados) |
| Claves o secretos en el cliente | ninguno |
| Rutas que llevan a un placeholder de una fase ya cerrada | **2 encontradas** |

---

## 3. Los dos callejones sin salida que se cerraron

### 3.1 El botón "+" de la app no hacía nada

El botón flotante de la pantalla "Hoy" —el más visible de toda la app— apuntaba
a `/missions/new`, que seguía siendo un placeholder de la Fase 2.

La causa de fondo es real y no un olvido: **una misión no existe sin objetivo**.
La entidad guarda `goalId`, `goalTitle` y `categoryId` desnormalizados, y el
formulario los necesita. El botón, en cambio, no sabe a qué objetivo apunta.

Se resolvió con un paso de elección (`PickGoalScreen`) en vez de un desplegable
dentro del formulario: mezclar las dos decisiones en una pantalla deja sin salida
clara el caso de no tener ningún objetivo. Ahí, la pantalla ofrece crear uno.

### 3.2 El historial de misiones

El botón de historial de la pantalla "Hoy" abría un placeholder que decía "llega
con el sistema de Aura" — un sistema terminado seis fases antes. El método
`getHistory` con cursor existía en el repositorio desde entonces, sin usar.

`MissionHistoryScreen` lo consume paginando con cursor y no con `offset`:
Firestore no tiene `offset` real —lo simula leyendo y descartando, y cobra igual
las lecturas descartadas—, así que la página diez costaría diez páginas.

Un test fija que un fallo al paginar **no borra lo ya traído**: perder la página
que se estaba leyendo por no poder traer la siguiente sería peor que el error.

---

## 4. `Page<T>` → `Paginated<T>`

La deuda que más ruido metía. El dominio tenía una clase `Page<T>` para
paginación y Flutter tiene su propio `Page` para navegación, así que **todo
archivo que tocara las dos** necesitaba esto:

```dart
import 'package:flutter/material.dart' hide Page;
```

Once archivos lo arrastraban, más dos que habían tenido que recurrir a un alias
(`as domain show Page`). Cada archivo nuevo que tocara paginación heredaba el
problema, y el síntoma —un error de tipos que no menciona el conflicto— cuesta
diez minutos la primera vez.

Renombrar la del dominio elimina la colisión de raíz: veintidós archivos, cero
`hide`, cero alias. Los 539 tests siguen pasando sin tocar ninguno.

Se renombró la del dominio y no la de Flutter por lo obvio, pero también porque
`Paginated<T>` **dice mejor lo que es**: una página de resultados con cursor, no
una pantalla.

---

## 5. Estado final del producto

### Aplicación móvil

| Área | Estado |
|---|---|
| Autenticación y perfil | ✅ email, Google, recuperación, verificación, borrado de cuenta |
| Objetivos | ✅ CRUD, hitos, progreso, cascada de borrado |
| Misiones | ✅ CRUD, "Hoy", historial paginado, dificultad, presupuesto |
| Evidencias | ✅ cola local; Storage pendiente de Blaze |
| Aura | ✅ server-authoritative, ledger, rachas, niveles |
| Comunidad | ✅ feed paginado, likes, comentarios, reportes |
| IA | ✅ vía Cloud Function; pendiente la API key |
| Integraciones | ✅ Open-Meteo y Open Library, sin clave |
| Notificaciones | ✅ bandeja, preferencias, deep links; push pendiente de credenciales |

### Panel de administración

| Sección | Estado |
|---|---|
| Dashboard, Usuarios, Reportes, Categorías, Auditoría | ✅ funcionales |
| Objetivos, Plantillas, Publicaciones, Analíticas, Configuración | 🔸 placeholder, marcado en el menú |

### Firebase

| Pieza | Estado |
|---|---|
| Reglas de Firestore | ✅ 115 tests; cerradas por defecto |
| Índices | ✅ al día, incluidos los de grupo de colección |
| Cloud Functions | ✅ 12 desplegables, 154 tests |
| Despliegue | ⏳ nunca ejecutado |

---

## 6. Requisitos académicos

| Requisito | Estado | Dónde |
|---|---|---|
| Dos aplicaciones | ✅ | `apps/ascend_mobile` + `apps/ascend_admin` |
| Un solo Firestore compartido en tiempo real | ✅ | ambas usan `ascend_data`; los streams son `snapshots()` |
| Reglas cerradas | ✅ | `backend/firestore.rules`, 115 tests |
| Dos roles como mínimo | ✅ | `user` / `admin` por custom claim (ADR-004) |
| Dos APIs externas como mínimo | ✅ | Open-Meteo, Open Library, y Gemini como tercera |
| Resiliencia: try/catch, validación, errores claros | ✅ | `Result`/`Failure`, `runGuarded`, `AsyncStateBuilder` |
| Sin pantallas rojas de Flutter | ✅ | `runAscendGuarded`: cuatro trampas, incluida `ErrorWidget.builder` |
| Manejo de offline | ✅ | persistencia de Firestore, `OfflineBanner`, cola de evidencias |

---

## 7. Lo que queda fuera del alcance de esta fase

El roadmap original de la Fase 9/10 incluía cosas que **no** se hicieron y que
conviene nombrar en vez de dejarlas implícitas:

- **Tests E2E con Patrol** de los cinco flujos críticos. Requieren un dispositivo
  o emulador y credenciales de Firebase; ninguna de las dos cosas existe acá.
- **Auditoría de performance** (arranque < 2 s, jank < 1 %, APK < 40 MB). Exige
  un build de release en un dispositivo real.
- **Build de release firmado**, App Bundle, TestFlight, Firebase Hosting.
- **Accesibilidad verificada con TalkBack y VoiceOver.** El código usa
  `Semantics` y respeta el escalado de texto hasta 1.5×, pero verificado con un
  lector de pantalla real no está.
- **Assets de tienda, política de privacidad y términos.**

Todo eso depende de un entorno que esta máquina no tiene. Está listado en el
informe final como lo que sigue.

---

## 8. Deuda técnica que queda anotada

| Qué | Dónde | Por qué se dejó |
|---|---|---|
| Fuentes por `google_fonts` en vez de empaquetadas | `ascend_ui/pubspec.yaml` | Depende de la red en el primer arranque en frío |
| Lógica de notificaciones duplicada en Dart y TS | `notification_usecases.dart` / `notification-service.ts` | Deliberado y probado en ambos lados; anotado por si una regla cambia |
| Búsqueda de usuarios local a la página traída | `admin_usecases.dart` | Firestore no busca subcadenas; la alternativa es un motor de búsqueda entero |
| Exportación CSV al portapapeles | `users_screen.dart` | Descargar un archivo en Flutter Web exige código específico de web |
| Hora del recordatorio sin desnormalizar | `daily-reminders.ts` | El barrido horario alcanza para el volumen actual |
| Seis secciones del panel en placeholder | `admin_router.dart` | Marcadas en el menú; no son del núcleo del producto |

---

## 9. BUG-001

**Sigue abierto**, y se documentó por qué en
[06-BUGS-CONOCIDOS.md](06-BUGS-CONOCIDOS.md). La corrección lleva aplicada desde
la auditoría inicial y hay un test que fija que App Check se activa y que su
fallo no aborta el arranque — pero eso **no lo cierra**: hace falta registrar una
cuenta contra `ascend-dev`, y eso exige `flutterfire configure`, que no se puede
correr desde acá.

Marcarlo como resuelto porque los tests pasan sería exactamente lo que el product
owner pidió no hacer.
