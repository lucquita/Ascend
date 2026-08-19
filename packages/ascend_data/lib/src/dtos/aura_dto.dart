import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Traducción de los documentos de Aura al dominio.
///
/// **No tiene métodos de escritura, y eso es el punto.** El saldo, el ledger y
/// el consumo diario los escribe exclusivamente el servidor (ADR-003); las
/// reglas rechazan cualquier escritura del cliente. Ofrecer acá un `toCreate`
/// sería exponer una operación que Firestore va a rechazar siempre.
abstract final class AuraDto {
  /// Lee el saldo desde el documento de perfil.
  ///
  /// El saldo vive embebido en `users/{uid}.aura` y no en su propia colección:
  /// se lee siempre junto al perfil, así que separarlo costaría una lectura
  /// extra en cada pantalla.
  static Aura auraFromUser(Map<String, dynamic> data) {
    final aura = _mapOf(data['aura']);
    return Aura(
      total: _intOf(aura['total']),
      level: _intOf(aura['level'], fallback: 1),
      levelName: _stringOf(aura['levelName'], fallback: 'Iniciado'),
      xpInLevel: _intOf(aura['xpInLevel']),
      xpForNextLevel: _intOf(aura['xpForNextLevel'], fallback: 100),
    );
  }

  /// Lee un asiento del ledger.
  static AuraEntry entryFromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => entryFromMap(
    snapshot.data() ?? const <String, dynamic>{},
    id: snapshot.id,
  );

  /// Lee un asiento desde un mapa plano.
  static AuraEntry entryFromMap(
    Map<String, dynamic> data, {
    required String id,
  }) {
    final ref = _mapOf(data['ref']);
    return AuraEntry(
      id: id,
      amount: _intOf(data['amount']),
      balanceAfter: _intOf(data['balanceAfter']),
      reason: AuraReason.fromWire(_nullableStringOf(data['reason'])),
      createdAt: _dateOf(data['createdAt']) ?? DateTime.now().toUtc(),
      refType: _nullableStringOf(ref['type']),
      refId: _nullableStringOf(ref['id']),
      multiplier: _doubleOf(data['multiplier'], fallback: 1),
      note: _nullableStringOf(data['note']),
    );
  }

  /// Lee la tabla de niveles desde `config/auraRules`.
  ///
  /// Devuelve la lista ordenada por Aura mínima. Si el documento no existe o
  /// está roto, devuelve una lista vacía y la pantalla lo resuelve mostrando
  /// solo el nivel actual: es preferible a inventar una tabla que no coincida
  /// con la que usa el servidor para calcular.
  static List<AuraLevel> levelsFromConfig(Map<String, dynamic> data) {
    final raw = data['levels'];
    if (raw is! List) {
      return const <AuraLevel>[];
    }

    final levels = <AuraLevel>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final name = _nullableStringOf(map['name']);
      if (name == null) {
        continue;
      }
      levels.add(
        AuraLevel(
          level: _intOf(map['level'], fallback: 1),
          name: name,
          minAura: _intOf(map['minAura']),
        ),
      );
    }

    levels.sort((a, b) => a.minAura.compareTo(b.minAura));
    return List<AuraLevel>.unmodifiable(levels);
  }

  static Map<String, dynamic> _mapOf(Object? value) => value is Map
      ? Map<String, dynamic>.from(value)
      : const <String, dynamic>{};

  static String _stringOf(Object? value, {String fallback = ''}) =>
      value is String && value.isNotEmpty ? value : fallback;

  static String? _nullableStringOf(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static int _intOf(Object? value, {int fallback = 0}) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    _ => fallback,
  };

  static double _doubleOf(Object? value, {double fallback = 0}) =>
      switch (value) {
        final double v => v,
        final num v => v.toDouble(),
        _ => fallback,
      };

  static DateTime? _dateOf(Object? value) => switch (value) {
    final Timestamp v => v.toDate().toUtc(),
    final DateTime v => v.toUtc(),
    _ => null,
  };
}
