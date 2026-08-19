# Fase 3 — Evidencias · Resultado

**Estado: completada dentro de lo posible sin Cloud Storage.** Fecha: 2026-08-14.

---

## 1. Verificación

| Comprobación | Estado | Evidencia |
|---|---|---|
| Formato | ✅ | `dart format --set-exit-if-changed .` → 0 cambios |
| Análisis estático | ✅ | `dart analyze --fatal-infos .` → *No issues found* |
| Tests de Dart | ✅ | **299** |
| Tests de reglas | ✅ | **89** contra el emulador |
| Tests de Functions | ✅ | 27 con vitest |

**Total: 415 tests en verde.** Desde 382 en la Fase 2B, se agregaron **33**:
21 de dominio, 6 de la cola y del uploader, y 6 de reglas de seguridad.

---

## 2. La restricción y cómo se resolvió

Cloud Storage requiere plan pago y el proyecto está en el gratuito. Eso **no**
impide construir la fase, porque lo que depende de Storage es una sola cosa: el
byte que viaja. Todo lo demás —validación, cola, estados, reglas, seguridad— es
independiente.

La solución es un **puerto**, `EvidenceUploader`, con dos implementaciones:

| Implementación | Cuándo |
|---|---|
| `UnavailableEvidenceUploader` | Hoy. Declara `isAvailable == false` y lanza un `QuotaFailure` tipado |
| Sobre `FirebaseStorage` | Cuando se habilite. **Es lo único que hay que escribir** |

No se simula una subida que no ocurre. La cola retiene la evidencia, la
interfaz dice *"tu foto queda guardada en el teléfono y se sube sola cuando lo
activemos"*, y nadie cree que el archivo viajó.

**Decisión deliberada:** con Storage apagado, `processPendingUploads` no intenta
subir ni cuenta reintentos. Gastar los 5 intentos contra un backend que sabemos
apagado descartaría evidencias que sí se van a poder subir.

---

## 3. Qué quedó construido

```
packages/ascend_domain/lib/src/
├── enums/enums.dart                    + EvidenceReviewStatus
├── entities/mission.dart               Evidence + reviewStatus, sizeBytes, isValidProof
└── usecases/evidence_usecases.dart     validación pura + 4 casos de uso

packages/ascend_data/lib/src/
├── datasources/local/evidence_outbox.dart   cola + PendingUpload con reintentos
└── repositories/evidence_repository_impl.dart   puerto EvidenceUploader

backend/firestore.rules                 + evidenceReviewNotSelfGranted()
backend/tests/                          + 6 casos de reglas
```

En el detalle de misión, la evidencia muestra su estado de archivo y de
revisión, y avisa cuántas fotos esperan subir.

---

## 4. Decisiones

### 4.1 Subida y revisión son estados independientes

`EvidenceUploadStatus` dice si el archivo llegó. `EvidenceReviewStatus` dice si
el contenido fue aceptado. Una evidencia puede estar `uploaded` **y** `rejected`
a la vez: subió perfecto, pero no corresponde.

Confundirlos haría que una foto rechazada por moderación se mostrara como "falló
al subir", que es un mensaje falso. `Evidence.isValidProof` combina ambos: hay
imagen **y** no fue rechazada.

### 4.2 Agujero de seguridad encontrado y cerrado ⚠️

Al agregar `reviewStatus` al modelo apareció un problema real: las reglas de
`missions` protegían `auraReward` y `ownerId`, pero **la evidencia era un mapa
libre**. Cualquiera podía escribir:

```js
{ status: 'completed', evidence: { reviewStatus: 'approved' } }
```

y acreditarse un logro con una foto inventada. La moderación habría sido
decorativa.

**Corrección:** helper `evidenceReviewNotSelfGranted()` en `firestore.rules`. El
cliente puede omitir el campo o dejarlo en `'pending'`; cualquier otro valor se
rechaza. Hay **6 tests** que lo verifican, incluido el ataque realista de colar
la aprobación dentro del completado de la misión.

El DTO tampoco manda el campo, pero eso es conveniencia: la regla es la defensa.

### 4.3 La validación vive en el dominio y es pura

`validateEvidenceFile` es una función sin dependencias: extensión, peso (10 MB,
el mismo `maxSize(10)` de `storage.rules`), archivo vacío y longitud de nota. Se
testea la tabla completa sin tocar disco ni Firebase.

Valida por extensión y no por MIME porque el dominio es Dart puro y no puede
leer el archivo. **Las reglas de Storage revalidan el `contentType` real**, que
es la comprobación que no se puede eludir. Esto es UX —evitar subir 10 MB por
red móvil para que el servidor los rechace—, no seguridad.

### 4.4 La cola es en memoria, no en Hive

`EvidenceOutbox` es una interfaz con implementación en memoria. `hive_ce` ya es
dependencia y pasar a disco es cambiar una línea del provider.

Se difiere a propósito: **sin Storage la cola no puede drenar nunca**, y
persistir en disco una cola que no vacía solo acumularía archivos huérfanos y
rutas locales que dejan de existir cuando el sistema limpia la caché. Se activa
junto con Storage, no antes.

### 4.5 La evidencia se anota antes de intentar subir

`enqueueUpload` escribe la evidencia en la misión con su `localPath` **primero**,
y encola después. Si el proceso muere en el medio, la persona ve su foto igual y
la cola la levanta al arrancar. Es lo que permite completar una misión en modo
avión.

---

## 5. Configuración pendiente — depende de vos

Para cerrar la fase de punta a punta hace falta **habilitar Cloud Storage**, que
requiere pasar el proyecto al plan Blaze:

1. Firebase Console → **Storage** → Comenzar, en `ascend-dev`.
2. Desplegar las reglas de Storage, que ya están escritas:
   ```bash
   cd backend && firebase deploy --only storage
   ```
3. Reemplazar `UnavailableEvidenceUploader` por la implementación sobre
   `FirebaseStorage` en `evidenceUploaderProvider`.
4. Cambiar `InMemoryEvidenceOutbox` por la versión sobre Hive.

Los pasos 3 y 4 son míos y quedan listos para hacerse en cuanto exista el 1.

**Nota de costos:** Blaze es de pago por uso con una capa gratuita generosa. Para
un proyecto escolar el gasto real esperado es cero o centavos, pero exige tarjeta.
No lo activo yo: es una decisión de facturación tuya.

---

## 6. Lo que no entró

- **Captura con cámara y galería.** `image_picker` y `flutter_image_compress` ya
  son dependencias. Se difiere junto con Storage: una pantalla que saca fotos
  que no pueden subir es una promesa que la app no puede cumplir.
- **Compresión a 1080px / JPEG q80.** Misma razón.
- **Generación de miniaturas en Function.** Requiere Storage por definición.
- **Reportes de evidencia.** La evidencia es privada por diseño
  (`storage.rules`: solo dueño y admin). Reportar contenido privado no tiene
  sentido; cobra sentido cuando se publica un logro, y ahí lo cubre el flujo de
  reportes de la Fase 5.
