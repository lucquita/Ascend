# Fase 9 — Notificaciones · Resultado

**Estado: completada a nivel de código.** Las push necesitan las credenciales
nativas para probarse de punta a punta (ver §7).
Fecha: 2026-08-18.

---

## 1. Verificación

| Comprobación | Estado | Evidencia |
|---|---|---|
| Formato | ✅ | `dart format --set-exit-if-changed .` → 0 cambios |
| Análisis estático | ✅ | `dart analyze --fatal-infos .` → *No issues found* |
| Tests de Dart | ✅ | **530** (+58) |
| Tests de Functions | ✅ | **154** (+36) |
| Tests de reglas | ✅ | 115 (sin cambios: no se tocó ninguna regla) |
| Lint + `tsc` | ✅ | limpios |

**Total: 799 tests en verde.** Desde 705 en la Fase 8, se agregaron **94**.

Desglose de los 530 de Dart: core 53 · domain 232 · data 109 · ui 28 · móvil 81
· admin 27.

---

## 2. La regla que ordena toda la fase

> Una notificación que molesta se desactiva — y cuando alguien las desactiva,
> se pierden también las que servían.

Cada decisión de esta fase sale de ahí. Es la razón de que el recordatorio no se
mande si no hay nada pendiente, de que cincuenta likes produzcan un solo aviso,
de que el horario de silencio guarde en vez de descartar, y de que exista una
explicación previa antes del diálogo del sistema.

---

## 3. Qué quedó construido

```
packages/ascend_domain/…/notification_usecases.dart
    isWithinQuietHours · isTypeEnabled · resolveDelivery
    groupKeyFor · groupedSocialBody · UnreadBadge
    OpenNotificationUseCase · EnableNotificationsUseCase

packages/ascend_data/…/firebase_messaging_datasource.dart   FCM envuelto
packages/ascend_data/…/notification_repository_impl.dart    bandeja + tokens
packages/ascend_data/…/dtos/notification_dto.dart

backend/functions/src/
├── services/notification-service.ts    espejo en TS de la lógica pura
├── lib/notifications.ts                deliver(): bandeja + push + limpieza
└── scheduled/daily-reminders.ts        recordatorio por hora local

apps/ascend_mobile/lib/features/notifications/
├── application/notifications_controller.dart
├── application/push_deep_links.dart          los tres estados de una push
├── presentation/screens/notifications_screen.dart
├── presentation/screens/notification_settings_screen.dart
└── presentation/widgets/notification_bell.dart
```

Y en los triggers de comunidad, el aviso agrupado al autor de una publicación.

---

## 4. Las decisiones que importan

### 4.1 La bandeja no depende de las push

Las notificaciones se leen de `users/{uid}/notifications`, que escribe el
servidor. FCM aporta solo el **aviso**: el sonido y la burbuja del sistema.

La consecuencia práctica es la que importa: sin permiso, sin token o sin
conexión en el momento del envío, **la información no se pierde**. Está en la
bandeja la próxima vez que se abre la app. Si la bandeja dependiera de las push,
rechazar el permiso equivaldría a no enterarse nunca de nada — y rechazarlo es
lo que hace la mitad de la gente.

### 4.2 El horario de silencio guarda, no descarta

`resolveDelivery` devuelve tres cosas distintas, no dos:

| Resultado | Cuándo | Qué pasa |
|---|---|---|
| `push` | tipo activo, fuera del silencio | bandeja + aviso del sistema |
| `inboxOnly` | tipo activo, en silencio | bandeja, sin sonar |
| `drop` | tipo apagado | nada |

Descartar en horario de silencio haría que alguien se entere de un comentario
solo si abre la app justo ese día. El interruptor pesa más que el silencio: si
fuera al revés, un tipo apagado seguiría llenando la bandeja.

### 4.3 El caso que se rompe siempre: la ventana nocturna

El horario de silencio típico es **22:00 a 07:00**. Ahí el inicio es mayor que
el fin, y la comparación ingenua `inicio <= t && t < fin` da `false` durante
**toda la noche** — exactamente cuando había que callarse.

```dart
return from < to
    ? current >= from && current < to
    : current >= from || current < to;   // ventana que cruza la medianoche
```

Hay cinco tests solo sobre esto, en las dos implementaciones. Además, un inicio
igual al fin **no** silencia las 24 horas: interpretarlo así apagaría las
notificaciones sin que nadie entienda por qué.

### 4.4 "Las 20:00" no es un momento

Es un momento **por zona horaria**. Una tarea diaria a una hora UTC fija le
llegaría a la mitad de la gente a media tarde y a la otra mitad de madrugada.

`dailyReminders` corre **cada hora en punto** y compara contra la hora local de
cada persona, calculada con `Intl` en el momento. No se guarda un desfase: el
desfase cambia dos veces al año con el horario de verano, y uno persistido se
desactualiza en silencio hasta que los recordatorios empiezan a llegar una hora
corridos.

Un test verifica que el mismo instante da tres horas distintas en Buenos Aires,
Madrid y Ciudad de México — que es el criterio de aceptación de la fase.

### 4.5 Cincuenta likes, una notificación

La agrupación se logra con un **id determinístico** por tipo, publicación y día:

```
new_like__p1__2026-08-17
```

La segunda entrega sobrescribe a la primera con el contador actualizado, en vez
de apilarse. Es la misma técnica que ya usan el ledger de Aura y los reportes.

El día forma parte de la clave a propósito: agrupar los likes de hoy con los de
la semana pasada daría un contador que nunca deja de crecer y una notificación
que nunca se siente nueva.

El texto se arma en el dominio y no en una plantilla del servidor porque la
pluralización en español no es "agregar una s": "1 persona más" y "2 personas
más" cambian el verbo que las acompaña.

### 4.6 La explicación previa al permiso

El diálogo del sistema se muestra **una sola vez**. Lanzarlo al abrir la app,
antes de que se entienda para qué sirve, hace que la mayoría lo rechace — y ese
rechazo solo se revierte desde los ajustes del sistema operativo, que casi nadie
abre.

Por eso la bandeja muestra primero una explicación propia, y el botón "Activar
avisos" aparece **solo** cuando el permiso está sin decidir. Con el permiso ya
denegado, en su lugar se explica que hay que ir a los ajustes del teléfono: un
botón que no puede hacer nada es peor que ninguno.

### 4.7 Los tres estados de una push

| Estado de la app | Cómo se maneja |
|---|---|
| Primer plano | No abre nada sola. Interrumpir a quien está usando la app es peor que esperar; el contador de la campana se actualiza solo porque escucha Firestore. |
| Segundo plano | `openedMessages()` emite al tocarla. |
| **Cerrada** | `initialMessage()` la entrega en el arranque. |

El tercero es el que se olvida siempre, y es justamente el del criterio de
aceptación: tocar una push con la app cerrada tiene que abrir la pantalla
exacta, no la inicial.

La navegación usa `push` y no `go`: quien llega desde afuera de la app tiene que
poder volver atrás a la pantalla principal en vez de quedar encerrado.

### 4.8 Tokens: rotación, limpieza y cierre de sesión

Tres cosas que suelen faltar y cuestan dinero o filtran datos:

- **Rotación.** FCM cambia el token solo —al reinstalar, al restaurar un backup,
  al limpiar los datos—. `tokenRefreshes()` vuelve a registrar. Sin esto, el
  dispositivo deja de recibir push en silencio.
- **Limpieza.** `sendPush` borra los tokens que el servidor rechaza como
  inválidos. Sin eso, cada envío posterior falla y se sigue pagando el intento.
- **Cierre de sesión.** `DeviceRegistrar` da de baja el token de la cuenta
  anterior. Sin eso, un teléfono compartido seguiría recibiendo las
  notificaciones de quien lo usó antes, que es una filtración de datos.

Además, el token **no se registra sin permiso**: sería dejar al servidor mandando
push que el sistema descarta, pagando cada envío.

### 4.9 Lo que no se puede apagar

Moderación, subida de nivel y anuncios del equipo no tienen interruptor. Son
pocos, no se repiten y avisan de algo que afecta a la cuenta. Un aviso de
moderación silenciado dejaría a alguien sin entender por qué desapareció su
publicación. La pantalla de ajustes lo dice explícitamente en vez de dejar que
se descubra por ausencia.

Un campo de preferencias **ausente** cuenta como encendido: es el valor por
defecto del perfil, y un `undefined` de un documento viejo no puede significar
"lo apagó".

---

## 5. La lógica está duplicada a propósito

`notification_usecases.dart` (Dart) y `notification-service.ts` (TypeScript)
implementan las mismas reglas. No es un descuido:

- El **envío ocurre en el servidor**, así que la decisión tiene que poder
  tomarse ahí sin consultar al cliente.
- La **app** necesita las mismas reglas para que los ajustes muestren lo que
  realmente va a pasar.

Las dos copias están probadas por separado **con los mismos casos límite** —la
ventana nocturna, el inicio igual al fin, el campo ausente, la pluralización—.
Eso es lo que evita que se separen sin que nadie lo note. Queda anotado como el
punto a revisar si alguna regla cambia.

---

## 6. Bug encontrado de paso

`NotificationSettingsController.save` leía el uid de `authStateProvider` y el
perfil de `profileProvider`. Los dos datos son el mismo, pero llegan por caminos
distintos: en un test —y en un arranque en frío real— el primero todavía no
emitió cuando el segundo ya está listo, y el guardado se descartaba en silencio
devolviendo `false`.

Se corrigió tomando el uid del propio perfil, que hace falta igual para no pisar
el tema, el idioma ni el huso horario al tocar un interruptor. Hay un test que
fija justamente eso.

---

## 7. Lo que queda pendiente de configuración externa

Las push **no se pueden probar de punta a punta en esta máquina**, por la misma
razón que BUG-001: faltan `google-services.json` y `firebase_options.dart`, que
son las credenciales nativas que genera `flutterfire configure`.

Lo que sí está verificado sin ellas:

- toda la lógica de decisión, en las dos implementaciones (71 tests);
- la bandeja, la campana, los ajustes y los estados de permiso (19 tests de
  widget);
- que la ausencia de FCM **no rompe nada**: el datasource devuelve `null` o
  `denied` y la app funciona entera sin avisos del sistema.

Para la prueba real hacen falta, en este orden:

1. `flutterfire configure` contra `ascend-dev`.
2. `firebase deploy --only functions:dailyReminders,functions:onLikeWrite,functions:onCommentWrite`.
3. En iOS, además, subir la clave APNs a la consola de Firebase.

---

## 8. Tests agregados (94)

| Suite | Cuántos | Qué fijan |
|---|---|---|
| `ascend_core/date_utils_test.dart` | 4 | `relativeLabel`: escala, tope en un mes y que una fecha futura no dé un número negativo —pasa cuando el reloj del dispositivo va atrasado— |
| `ascend_domain/notification_usecases_test.dart` | 35 | Ventana nocturna, inicio igual al fin, interruptor por tipo, silencio que guarda, claves de agrupación, pluralización, insignia 99+, permiso |
| `ascend_mobile/notifications_screens_test.dart` | 19 | Bandeja, marcado al abrir, navegación al destino, explicación del permiso según su estado, insignia, guardado de preferencias sin pisar el resto |
| `functions/notification-service.test.ts` | 36 | El espejo en TS de todo lo anterior, más husos horarios reales, ventana horaria del recordatorio y riesgo de racha |

---

## 9. Lo que esta fase deliberadamente no hizo

- **No hay notificaciones masivas segmentadas** desde el panel: son de la lista
  de administración avanzada, no del núcleo del producto.
- **No se desnormalizó la hora UTC del recordatorio.** El barrido horario
  consulta a quienes lo tienen activo y filtra en memoria. A escala grande
  convendría guardar la hora ya convertida para consultar solo a quienes les
  toca; queda anotado en el propio archivo.
- **En primer plano no se muestra nada.** Interrumpir a quien está usando la app
  con un cartel de lo que ya está viendo es ruido; la campana se actualiza sola.

---

## 10. Estado tras la fase

| | Estado |
|---|---|
| Móvil | Completa: objetivos, misiones, evidencias, Aura, comunidad, IA, integraciones y notificaciones |
| Admin | Funcional con 5 secciones reales |
| Firebase | 3 funciones nuevas; reglas e índices al día; falta desplegar |
| Pendiente externo | `flutterfire configure` · API key de Gemini · Cloud Storage (Blaze) · clave APNs · verificación de BUG-001 |

Siguiente: **Fase 10 — QA y pre-lanzamiento**, que incluye el renombrado de
`Page<T>` a `Paginated<T>` y el informe final.
