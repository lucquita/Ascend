# Fase 5 — Comunidad · Resultado

**Estado: completada.** Fecha: 2026-08-14.

---

## 1. Verificación

| Comprobación | Estado | Evidencia |
|---|---|---|
| Formato | ✅ | `dart format --set-exit-if-changed .` → 0 cambios |
| Análisis estático | ✅ | `dart analyze --fatal-infos .` → *No issues found* |
| Tests de Dart | ✅ | **341** (+31) |
| Tests de reglas | ✅ | **103** (+6) |
| Tests de Functions | ✅ | 63 |
| Lint + `tsc` | ✅ | limpios |

**Total: 507 tests en verde.** Desde 470 en la Fase 4, se agregaron **37**.

---

## 2. Qué quedó construido

```
packages/ascend_domain/lib/src/
├── entities/post.dart                Post · Comment · Report · PostAuthor · PostSource
├── usecases/community_usecases.dart  validación pura + reglas de visibilidad
└── repositories/repositories.dart    + Post/Comment/Report/PublicProfile

packages/ascend_data/lib/src/
├── dtos/post_dto.dart                4 DTOs, ninguno escribe campos del servidor
├── datasources/remote/firestore_community_datasource.dart
└── repositories/community_repository_impl.dart

apps/ascend_mobile/lib/features/community/
├── application/community_controller.dart   feed paginado + escrituras
└── presentation/
    ├── screens/  feed · post_detail · create_post
    └── widgets/  PostCard · CommentTile · AuthorAvatar

backend/functions/src/triggers/community.ts
    onPostCreate · onPostDelete · onLikeWrite · onCommentWrite · onReportCreate
```

Las rutas `/community`, `/community/create` y `/community/post/:postId` ya no
son placeholders.

---

## 3. La premisa del producto, como regla verificable

*El feed solo muestra logros reales.* Eso no es una frase de marketing: está
codificado en tres capas.

1. **Dominio** — `validatePost` rechaza un post de logro sin `source`. Solo las
   reflexiones quedan exentas. Incluye el caso de esquive obvio: mandar un
   `source` vacío tampoco cuenta.
2. **Reglas de Firestore** — la misma condición, del lado del servidor, porque
   una validación de pantalla se esquiva con `curl`.
3. **Interfaz** — publicar un logro es *elegir de una lista* de misiones
   completadas, no escribir a mano. El camino fácil es el correcto.

Además, `canPublishMission` impide publicar una misión que no se completó: es
exactamente el "logro falso" que el sistema de reportes existe para perseguir, y
conviene frenarlo antes de que exista.

---

## 4. Lo que el cliente no puede escribir

Las reglas rechazan tres campos al crear una publicación, y hay un test por cada
uno:

| Campo | Por qué |
|---|---|
| `counters` | Si el cliente los fijara, nacería con mil "me gusta" |
| `moderation` | Autoaprobarse contenido dejaría la moderación en decorado |
| `author` | Publicaría con el nombre y el nivel de otra persona |

Los tres los mantienen triggers. Se agregó también el caso de **inflarse los
propios contadores al editar**: ser dueño del post no habilita a escribir lo que
mantiene el servidor.

---

## 5. Decisiones

### 5.1 Likes y reportes son idempotentes por la clave, no por consulta

El documento de like tiene el **uid como id**; el de reporte,
`{targetId}_{reporterId}`. Consecuencias: no existe forma de dar like dos veces
ni de inflar el contador de reportes reportando cien veces, y saber si ya diste
like cuesta **una lectura por id** en vez de una consulta.

Es la misma técnica en los dos casos, y es lo que hace que el umbral de
auto-ocultado signifique algo: tres reportes son necesariamente de **tres
personas distintas**.

### 5.2 Auto-ocultado a los tres reportes

`onReportCreate` cuenta en una transacción y, al llegar a tres, pasa el post a
`under_review`. Ocultar primero y revisar después es lo correcto: el daño de
dejar visible algo abusivo unas horas supera al de ocultar algo legítimo por
error, que se revierte desde el panel.

**El autor sigue viendo su propio contenido oculto.** Esconderle su publicación
sin explicación lo dejaría creyendo que se perdió.

### 5.3 El autor va desnormalizado dentro del post

Una página de 20 publicaciones cuesta **20 lecturas, no 40**: sin la copia, cada
post exigiría leer también el perfil de quien lo escribió. Se copia de
`publicProfiles` y nunca de `users`, que tiene email y ajustes privados.

### 5.4 El like se aplica de forma optimista

El contador real lo mantiene un trigger y tarda un instante. Sin el ajuste local,
tocar el corazón no haría nada visible durante ese lapso y la gente lo tocaría
dos veces. Hay un test que lo verifica.

### 5.5 `hasReported` responde `false` ante `permission-denied`

Un usuario común **no puede leer** `reports`: solo el admin. Ese rechazo no es un
error a mostrar, es la respuesta esperada y significa "no puedo saberlo". Se
responde `false` para que la pantalla ofrezca reportar; si ya lo había hecho, la
escritura sobrescribe el mismo documento y no infla nada.

---

## 6. Dos bugs propios encontrados por los tests

### 6.1 Lanzar dentro de un `build()` asincrónico colgaba el feed ⚠️

`FeedController.build()` relanzaba el `Failure` para que el `AsyncValue` quedara
en error. **No funciona**: el provider se quedaba en `AsyncLoading` para siempre
y la pantalla mostraba skeletons girando en vez del error. Lo detectó un test que
imprimía los textos renderizados: solo aparecían el título y el botón, nada del
cuerpo.

Corregido alineándolo con el patrón del resto del proyecto: el provider emite
`Result<FeedState>` y **nunca lanza**; la pantalla lo pinta con `fold`.

Es el mismo modo de fallo que el producto no admite —quedarse cargando sin
explicar nada— y ya había aparecido en la Fase 2A con los streams vacíos.

### 6.2 Faltaban los mensajes de comunidad

Agregué ocho claves de validación al dominio y **olvidé darlas de alta** en
`failure_messages.dart`, así que todas caían al genérico *"Hay algo que corregir
antes de continuar"*. Un test de widget que esperaba el mensaje concreto lo
delató.

---

## 7. Lo que no entró

- **Seguir / dejar de seguir** y la pestaña "Siguiendo". El grafo social ya
  tiene sus reglas desde la Fase 0; falta la interfaz y los contadores.
- **Perfil público de otra persona** (`/u/:handle`). El repositorio está hecho y
  testeado; falta la pantalla.
- **Moderación por IA previa a la publicación.** Depende de Gemini (Fase 6). Hasta
  entonces el contenido nace visible y el sistema de reportes lo cubre, que es lo
  que hace cualquier red social sin moderación previa.
- **Bloqueo de usuarios.**
- **Respuestas a comentarios.** El modelo soporta un nivel (`parentId`); la
  interfaz todavía muestra el hilo plano.

---

## 8. Configuración pendiente

Se suman cinco triggers al despliegue:

```bash
cd backend && firebase deploy --only firestore:rules,firestore:indexes,functions
```

Los índices del feed —`moderation.status + createdAt` y `authorId + createdAt`—
ya estaban declarados desde la Fase 0.
