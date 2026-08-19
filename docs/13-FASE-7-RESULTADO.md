# Fase 7 — APIs e integraciones · Resultado

**Estado: completada.** Sin configuración externa pendiente: las dos APIs
funcionan hoy, sin clave.
Fecha: 2026-08-17.

---

## 1. Verificación

| Comprobación | Estado | Evidencia |
|---|---|---|
| Formato | ✅ | `dart format --set-exit-if-changed .` → 0 cambios |
| Análisis estático | ✅ | `dart analyze --fatal-infos .` → *No issues found* |
| Tests de Dart | ✅ | **404** (+48) |
| Tests de Functions | ✅ | 90 (sin cambios: la fase no tocó el backend) |
| Tests de reglas | ✅ | 103 (sin cambios: no se tocó ninguna regla) |
| Lint + `tsc` | ✅ | limpios |

**Total: 597 tests en verde.** Desde 549 en la Fase 6, se agregaron **48**.

Desglose de los 404 de Dart: core 39 · domain 166 · data 109 · ui 28 · móvil 62.

---

## 2. Por qué estas dos APIs

El criterio de selección fue **que se puedan mostrar el día de la defensa**.
Gemini (Fase 6) y Cloud Storage (Fase 3) están bien resueltos a nivel de código
pero dependen de una clave y de un plan de facturación que nadie cargó todavía.
Una tercera integración con el mismo problema habría sido una funcionalidad
imposible de demostrar.

| API | Qué resuelve | Clave | Costo |
|---|---|---|---|
| **Open-Meteo** | Si va a llover el día de una misión al aire libre | No | Gratis, sin registro |
| **Open Library** | Convertir "leer más" en "leer *este* libro" | No | Gratis, sin registro |

Las dos son de uso libre para proyectos no comerciales y no exigen cuenta. Eso
cumple el requisito académico de **dos APIs externas** *y* deja la demo andando
en cualquier máquina con internet.

Ninguna de las dos es decorativa. Cada una responde a una falla concreta del
producto:

- **El clima rompe rachas.** Una misión de correr programada para un día de
  tormenta se incumple, y en una app cuyo eje es la constancia eso cuesta caro.
  Avisar con días de anticipación permite moverla antes de perderla.
- **"Leer más" no se puede completar.** Una misión sin criterio de finalización
  es una que nunca se marca hecha. Con el libro elegido —título, autor,
  páginas— la misión se sabe cumplida y la app puede estimar cuánto lleva.

---

## 3. Qué quedó construido

```
packages/ascend_domain/lib/src/usecases/integration_usecases.dart
    WeatherForecast · WeatherCondition (códigos WMO) · BookSuggestion
    WeatherRepository · BookRepository            (puertos, sin Flutter)
    needsWeatherCheck · CheckMissionWeatherUseCase
    SearchBooksUseCase · difficultyForBook · suggestsBooks
    Coordinates · coordinatesForTimezone

packages/ascend_data/lib/src/datasources/remote/ascend_http_client.dart
    Cliente HTTP único: timeout, reintentos, rechazo de portales cautivos

packages/ascend_data/lib/src/repositories/integration_repository_impl.dart
    WeatherRepositoryImpl (Open-Meteo) · BookRepositoryImpl (Open Library)

apps/ascend_mobile/lib/features/integrations/
├── application/integrations_controller.dart      providers
└── presentation/widgets/book_picker.dart         hoja modal de búsqueda
```

Y dos puntos de contacto con la UI existente:

- `mission_detail_screen.dart` — `_WeatherHint`, el aviso de clima.
- `mission_form_screen.dart` — el botón "Elegir un libro del catálogo".

---

## 4. Las decisiones que importan

### 4.1 Ninguna integración externa puede bloquear la app

Es la regla que ordena toda la fase. Una API de terceros es la parte del sistema
sobre la que menos control se tiene: puede tardar, caerse, cambiar su contrato o
devolver el HTML de un portal cautivo de wifi de aeropuerto.

`CheckMissionWeatherUseCase` **devuelve `null`, nunca un `Failure`**, y está
comentado así en el código. Si Open-Meteo no responde, el aviso simplemente no
aparece y la misión se hace igual. Hay un test que lo fija
(`si la API falla la misión se muestra igual`): verifica que con la API caída el
título de la misión y el botón "Completar misión" siguen a la vista.

El buscador de libros sí propaga el error, porque ahí la persona **pidió** una
búsqueda y merece saber que no salió, con un botón de reintento. La diferencia
es quién inició la acción.

### 4.2 Un solo cliente HTTP, con la política de reintentos que ya existía

`AscendHttpClient` reutiliza `RetryPolicy` de `ascend_core` en vez de traer una
segunda forma de reintentar. Lo que agrega:

- **Timeout explícito de 10 s.** Sin él, `http` espera el del sistema operativo,
  que en redes móviles malas puede ser más de un minuto de spinner.
- **Reintento selectivo.** Un 5xx o un corte de red se reintentan; un 404 no.
  Reintentar un 404 no lo convierte en un 200: solo gasta batería y datos.
- **Rechazo de respuestas no-JSON.** Un portal cautivo devuelve `200 OK` con
  HTML. Sin esta comprobación el parseo fallaría con un error críptico en vez de
  con "no se pudo conectar".
- **Logging que no filtra.** Se registran host y path, nunca el query string ni
  el cuerpo. Un término de búsqueda de libros es un dato personal.

### 4.3 Ubicación sin GPS

El clima necesita coordenadas. La solución obvia sería pedir permiso de
ubicación, y es la equivocada: pedir GPS para decir si va a llover es
desproporcionado, mucha gente lo niega, y la funcionalidad muere ahí. Además
habría exigido una dependencia nueva (`geolocator`) y permisos en el manifiesto.

En su lugar se usa el **huso horario que ya está en el perfil**
(`coordinatesForTimezone`), con un mapa de doce ciudades de la región. Da
precisión de ciudad, que es exactamente la que necesita un pronóstico diario.
Huso desconocido → `null` → no se consulta nada: preferible a mostrar el
pronóstico de otro continente.

### 4.4 Se consulta solo cuando puede cambiar una decisión

`needsWeatherCheck` exige las tres condiciones a la vez:

1. categoría al aire libre (`fitness`, `travel`),
2. la misión tiene fecha,
3. la fecha cae dentro de los próximos 7 días.

Una misión de lectura no mejora por saber que llueve, y más allá de una semana
el pronóstico deja de ser confiable —Open-Meteo tampoco lo ofrece—. Cada llamada
evitada es batería y datos que no se gastan. Un test verifica que una misión de
`reading` **no genera ninguna llamada** (`weather.calls == 0`).

### 4.5 Umbrales pensados para que el aviso se siga leyendo

El aviso aparece con **≥60 % de probabilidad de lluvia**, o con tormenta a
cualquier probabilidad. Avisar con 20 % sería alarmismo: la gente aprende a
ignorar el aviso y termina siendo peor que no darlo.

Los códigos WMO desconocidos se mapean a `WeatherCondition.unknown` en lugar de
adivinar. Un pronóstico equivocado es peor que uno ausente.

### 4.6 La sugerencia asiste, no decide

Elegir un libro **rellena** el formulario —título, dificultad según extensión,
duración estimada— y lo deja editable. No crea la misión ni cierra la pantalla.

La duración sale de las páginas a 40 páginas por hora, un ritmo conservador, y
se acota a 480 minutos: un libro entero no es una misión sino un objetivo, y
proponerlo como una tarea de veinte horas sería absurdo.

El botón aparece solo en objetivos de `reading` y `languages` (`suggestsBooks`).
En una categoría de gimnasio sería un botón que nadie va a tocar, ensuciando el
formulario.

### 4.7 Detalles de red que se pagan del lado del usuario

- **Open-Meteo**: se piden exactamente tres campos diarios
  (`weather_code`, `temperature_2m_max`, `precipitation_probability_max`), no el
  pronóstico horario completo.
- **Open Library**: se usa el parámetro `fields` para recortar la respuesta, que
  por defecto trae decenas de campos por resultado.
- **Debounce de 350 ms** en el buscador, reutilizando el `Debouncer` que ya usa
  el registro. Sin él saldría una llamada por tecla contra un catálogo gratuito
  que nos deja consultarlo por buena voluntad.
- **Mínimo de 3 caracteres**, validado en el caso de uso *y* en la UI. La UI no
  muestra el rechazo como error: mientras la consulta es corta se ve
  "Escribí un título", porque la persona todavía no terminó de escribir.
- Los resultados sin título se descartan en el repositorio, en vez de pintar
  filas vacías.

---

## 5. Dependencia agregada: `http: ^1.6.0`

Una sola, y declarada explícita en `packages/ascend_data/pubspec.yaml` aunque ya
estaba en el árbol como transitiva de `firebase_*`. Depender de una transitiva es
frágil: desaparece en cuanto quien la arrastraba cambia de implementación.

Se verificó antes de agregarla que el proyecto no tuviera ya un cliente HTTP
propio, y que la versión fuera compatible con el Flutter fijado. `MockClient`
(de `http/testing.dart`) permite además probar toda la capa de red sin tocar
internet: los 18 tests de la capa de red corren sin conexión.

---

## 6. Tests agregados (48)

| Suite | Cuántos | Qué fijan |
|---|---|---|
| `ascend_data/integration_repository_test.dart` | 18 | El cliente HTTP como frontera: 404 sin reintento, 5xx con reintento, HTML rechazado, JSON malformado, parseo que lanza, 429 → cuota, sin red → `NetworkFailure`. Mapeo de ambas APIs. |
| `ascend_domain/integration_usecases_test.dart` | 21 | Cuándo se consulta el clima y cuándo no, que un fallo devuelve `null`, umbrales de lluvia, códigos WMO, mínimo de caracteres, estimación y tope de duración, dificultad por extensión, dónde se ofrece el catálogo. |
| `ascend_mobile/integrations_screens_test.dart` | 9 | El aviso aparece con mal clima y no con buen clima; con la API caída la misión sigue usable; una misión de lectura no gasta una llamada. El buscador: debounce, resultados, elección devuelta, "sin resultados" ≠ error, reintento. |

---

## 7. Lo que esta fase deliberadamente no hizo

- **No se tocaron las reglas de Firestore.** Ninguna integración escribe: el
  clima no se persiste y el libro elegido termina siendo texto de la misión, que
  ya tenía sus reglas. Los 103 tests de reglas quedaron intactos.
- **No se cachea el pronóstico.** Con la consulta limitada a misiones de
  exterior con fecha próxima, el volumen es bajo; una caché sumaría invalidación
  y estado sin resolver un problema real.
- **No se agregó una tercera API.** Dos cumplen el requisito y cada una tiene
  una razón de producto. Una tercera sería relleno.

---

## 8. Estado tras la fase

| | Estado |
|---|---|
| Móvil | Objetivos, misiones, evidencias, Aura, comunidad, IA e integraciones funcionando |
| Admin | **Sigue en placeholders** — es el trabajo de la Fase 8 |
| Firebase | Reglas e índices escritos y probados; falta desplegarlos |
| Pendiente externo | API key de Gemini · Cloud Storage (Blaze) · verificación de BUG-001 |

Siguiente: **Fase 8 — Panel de administración**, que es además el requisito
académico todavía incumplido (dos aplicaciones reales, no una y una maqueta).
