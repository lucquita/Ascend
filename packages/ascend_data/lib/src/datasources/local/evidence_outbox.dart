import 'dart:async';

import 'package:ascend_core/ascend_core.dart';
import 'package:meta/meta.dart';

/// Una evidencia esperando su turno para subir.
@immutable
class PendingUpload {
  /// Crea una entrada de la cola.
  const PendingUpload({
    required this.id,
    required this.uid,
    required this.missionId,
    required this.localPath,
    required this.queuedAt,
    this.note,
    this.attempts = 0,
    this.lastError,
  });

  /// Reconstruye una entrada desde su forma persistida.
  factory PendingUpload.fromMap(Map<String, Object?> map) => PendingUpload(
    id: map['id']! as String,
    uid: map['uid']! as String,
    missionId: map['missionId']! as String,
    localPath: map['localPath']! as String,
    queuedAt:
        DateTime.tryParse(map['queuedAt'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    note: map['note'] as String?,
    attempts: (map['attempts'] as num?)?.toInt() ?? 0,
    lastError: map['lastError'] as String?,
  );

  /// Identificador de la entrada. Ordenable cronológicamente.
  final String id;

  /// Dueño de la evidencia.
  final String uid;

  /// Misión a la que pertenece.
  final String missionId;

  /// Ruta del archivo en el dispositivo.
  final String localPath;

  /// Cuándo entró en la cola.
  final DateTime queuedAt;

  /// Nota escrita por la persona.
  final String? note;

  /// Intentos fallidos acumulados.
  final int attempts;

  /// Último error, para poder explicar por qué no subió.
  final String? lastError;

  /// Serializa la entrada.
  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'uid': uid,
    'missionId': missionId,
    'localPath': localPath,
    'queuedAt': queuedAt.toIso8601String(),
    'note': note,
    'attempts': attempts,
    'lastError': lastError,
  };

  /// Copia registrando un intento fallido.
  PendingUpload withFailure(String error) => PendingUpload(
    id: id,
    uid: uid,
    missionId: missionId,
    localPath: localPath,
    queuedAt: queuedAt,
    note: note,
    attempts: attempts + 1,
    lastError: error,
  );

  /// `true` si ya agotó los reintentos.
  ///
  /// Sin un techo, una evidencia rota —archivo borrado, permiso revocado— se
  /// reintentaría para siempre gastando batería y datos en cada reconexión.
  bool get isExhausted => attempts >= maxAttempts;

  /// Reintentos antes de dar la subida por fallida.
  static const int maxAttempts = 5;
}

/// Cola persistente de evidencias pendientes de subir.
///
/// Es el "outbox" del ADR de resiliencia: Firestore ya sincroniza solo sus
/// documentos, pero **no** sube archivos. Sin esta cola, completar una misión
/// sin conexión perdería la foto.
abstract interface class EvidenceOutbox {
  /// Agrega una entrada.
  Future<void> enqueue(PendingUpload upload);

  /// Quita una entrada por id.
  Future<void> remove(String id);

  /// Reemplaza una entrada (por ejemplo, tras un intento fallido).
  Future<void> update(PendingUpload upload);

  /// Todas las entradas, de la más vieja a la más nueva.
  Future<List<PendingUpload>> pending();

  /// Emite cuántas quedan pendientes.
  Stream<int> watchCount();

  /// Vacía la cola. Se usa al cerrar sesión.
  Future<void> clear();
}

/// Implementación en memoria.
///
/// La usan los tests y sirve de reserva si Hive no se pudo abrir: preferimos
/// una cola que se pierde al cerrar la app antes que una app que no arranca.
class InMemoryEvidenceOutbox implements EvidenceOutbox {
  final Map<String, PendingUpload> _items = <String, PendingUpload>{};
  final StreamController<int> _counts = StreamController<int>.broadcast();

  @override
  Future<void> enqueue(PendingUpload upload) async {
    _items[upload.id] = upload;
    _emit();
  }

  @override
  Future<void> remove(String id) async {
    _items.remove(id);
    _emit();
  }

  @override
  Future<void> update(PendingUpload upload) async {
    _items[upload.id] = upload;
    _emit();
  }

  @override
  Future<List<PendingUpload>> pending() async {
    final items = _items.values.toList()
      ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return List<PendingUpload>.unmodifiable(items);
  }

  @override
  Stream<int> watchCount() async* {
    yield _items.length;
    yield* _counts.stream;
  }

  @override
  Future<void> clear() async {
    _items.clear();
    _emit();
  }

  /// Cierra el stream. Solo para tests.
  @visibleForTesting
  Future<void> dispose() => _counts.close();

  void _emit() {
    if (!_counts.isClosed) {
      _counts.add(_items.length);
    }
  }
}

/// Genera el id de una entrada de la cola.
///
/// Ordenable cronológicamente para poder procesar en orden de llegada sin leer
/// el contenido de cada entrada.
String newUploadId() => IdGenerator.generateSortable();
