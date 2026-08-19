import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Traducción de `adminStats/{id}` a las métricas del panel.
abstract final class AdminStatsDto {
  /// Convierte un documento en las métricas.
  ///
  /// Todos los contadores caen a cero si faltan, salvo la fecha de generación,
  /// que cae a la época. Es deliberado: una fecha inventada "de ahora" haría
  /// que el panel diera por buenas unas métricas que en realidad no se
  /// calcularon nunca, en vez de avisar que están viejas.
  static AdminStats fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return AdminStats(
      generatedAt:
          _dateOf(data['generatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      usersTotal: _intOf(data['usersTotal']),
      usersActive7d: _intOf(data['usersActive7d']),
      usersNew7d: _intOf(data['usersNew7d']),
      goalsActive: _intOf(data['goalsActive']),
      missionsCompleted7d: _intOf(data['missionsCompleted7d']),
      auraGranted7d: _intOf(data['auraGranted7d']),
      postsTotal: _intOf(data['postsTotal']),
      reportsOpen: _intOf(data['reportsOpen']),
      aiCallsToday: _intOf(data['aiCallsToday']),
      aiCostUsdToday: _doubleOf(data['aiCostUsdToday']),
    );
  }

  static int _intOf(Object? value) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    _ => 0,
  };

  static double _doubleOf(Object? value) => switch (value) {
    final double v => v,
    final num v => v.toDouble(),
    _ => 0,
  };

  /// La función programada escribe la fecha en ISO 8601, pero un documento
  /// escrito a mano podría traer un `Timestamp`. Se aceptan los dos.
  static DateTime? _dateOf(Object? value) => switch (value) {
    final Timestamp v => v.toDate(),
    final String v => DateTime.tryParse(v),
    _ => null,
  };
}

/// Traducción de `auditLog/{id}` a una entrada del registro.
abstract final class AuditEntryDto {
  /// Convierte un documento en la entrada.
  static AuditEntry fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();

    // Los campos propios de cada acción —rol anterior, motivo, resolución— se
    // guardan sueltos en el documento. Se recogen en `details` en vez de
    // enumerarlos: así una acción nueva aparece en el panel sin tener que
    // tocar este mapeo, que es justamente lo que hace inútil a una auditoría
    // que se queda corta.
    const known = <String>{
      'action',
      'actorUid',
      'targetUid',
      'targetId',
      'createdAt',
    };

    return AuditEntry(
      id: snapshot.id,
      action: _stringOf(data['action'], fallback: 'unknown'),
      actorUid: _stringOf(data['actorUid'], fallback: 'desconocido'),
      targetUid: _nullableStringOf(data['targetUid']),
      targetId: _nullableStringOf(data['targetId']),
      details: <String, Object?>{
        for (final entry in data.entries)
          if (!known.contains(entry.key) && entry.value != null)
            entry.key: entry.value,
      },
      createdAt: switch (data['createdAt']) {
        final Timestamp v => v.toDate(),
        final String v =>
          DateTime.tryParse(v) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        _ => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      },
    );
  }

  static String _stringOf(Object? value, {required String fallback}) =>
      value is String && value.isNotEmpty ? value : fallback;

  static String? _nullableStringOf(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
