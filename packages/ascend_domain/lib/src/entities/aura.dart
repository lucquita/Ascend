import 'package:ascend_domain/src/enums/enums.dart';
import 'package:meta/meta.dart';

/// Saldo de Aura y nivel alcanzado.
///
/// Es un valor **de solo lectura para el cliente**: lo calcula el servidor. La
/// app lo muestra, nunca lo escribe. Ver ADR-003.
@immutable
class Aura {
  /// Crea un saldo de Aura.
  const Aura({
    required this.total,
    required this.level,
    required this.levelName,
    required this.xpInLevel,
    required this.xpForNextLevel,
  });

  /// Saldo inicial de una cuenta nueva.
  static const Aura initial = Aura(
    total: 0,
    level: 1,
    levelName: 'Iniciado',
    xpInLevel: 0,
    xpForNextLevel: 100,
  );

  /// Aura acumulada histórica.
  final int total;

  /// Nivel actual.
  final int level;

  /// Nombre del nivel ("Constante", "Imparable").
  final String levelName;

  /// Aura acumulada dentro del nivel actual.
  final int xpInLevel;

  /// Aura necesaria para pasar al siguiente nivel.
  final int xpForNextLevel;

  /// Avance dentro del nivel, entre 0.0 y 1.0.
  double get levelProgress {
    if (xpForNextLevel <= 0) {
      return 1;
    }
    return (xpInLevel / xpForNextLevel).clamp(0.0, 1.0);
  }

  /// Cuánta Aura falta para subir de nivel.
  int get remainingForNextLevel =>
      (xpForNextLevel - xpInLevel).clamp(0, xpForNextLevel);

  /// Copia con cambios.
  Aura copyWith({
    int? total,
    int? level,
    String? levelName,
    int? xpInLevel,
    int? xpForNextLevel,
  }) => Aura(
    total: total ?? this.total,
    level: level ?? this.level,
    levelName: levelName ?? this.levelName,
    xpInLevel: xpInLevel ?? this.xpInLevel,
    xpForNextLevel: xpForNextLevel ?? this.xpForNextLevel,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Aura &&
          other.total == total &&
          other.level == level &&
          other.levelName == levelName &&
          other.xpInLevel == xpInLevel &&
          other.xpForNextLevel == xpForNextLevel;

  @override
  int get hashCode =>
      Object.hash(total, level, levelName, xpInLevel, xpForNextLevel);
}

/// Asiento del libro mayor de Aura.
///
/// El ledger es append-only y lo escribe únicamente el servidor. Permite
/// auditar, graficar la evolución y recalcular el saldo desde cero si hiciera
/// falta revertir un exploit.
@immutable
class AuraEntry {
  /// Crea un asiento del ledger.
  const AuraEntry({
    required this.id,
    required this.amount,
    required this.balanceAfter,
    required this.reason,
    required this.createdAt,
    this.refType,
    this.refId,
    this.multiplier = 1.0,
    this.note,
  });

  /// Identificador del asiento.
  final String id;

  /// Aura otorgada (positiva) o quitada (negativa).
  final int amount;

  /// Saldo resultante después de aplicar este asiento.
  final int balanceAfter;

  /// Por qué se otorgó.
  final AuraReason reason;

  /// Momento del asiento (hora del servidor).
  final DateTime createdAt;

  /// Tipo del documento que lo originó (`mission`, `goal`).
  final String? refType;

  /// Identificador del documento que lo originó.
  final String? refId;

  /// Multiplicador aplicado (por ejemplo, bonificación de racha).
  final double multiplier;

  /// Explicación legible ("Racha de 12 días ×1.5").
  final String? note;

  /// `true` si el asiento suma Aura.
  bool get isGain => amount > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AuraEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Definición de un nivel, tal como viene de `config/auraRules`.
@immutable
class AuraLevel {
  /// Crea la definición de un nivel.
  const AuraLevel({
    required this.level,
    required this.name,
    required this.minAura,
  });

  /// Número de nivel.
  final int level;

  /// Nombre del nivel.
  final String name;

  /// Aura mínima para alcanzarlo.
  final int minAura;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AuraLevel && other.level == level;

  @override
  int get hashCode => level.hashCode;
}
