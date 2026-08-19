/// Casos de uso de Aura.
///
/// Todos son de **lectura**. No existe un `GrantAuraUseCase` y esa ausencia es
/// deliberada: el cliente no otorga Aura ni puede pedir que se le otorgue. La
/// única acción que la genera es completar una misión, y de eso se encarga un
/// trigger del servidor (ADR-003).
library;

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/src/entities/aura.dart';
import 'package:ascend_domain/src/entities/category.dart';
import 'package:ascend_domain/src/repositories/repositories.dart';

/// Observa el saldo y el nivel.
class WatchAuraUseCase {
  /// Crea el caso de uso.
  const WatchAuraUseCase(this._aura);

  final AuraRepository _aura;

  /// Emite el saldo cada vez que el servidor lo actualiza.
  Stream<Result<Aura>> call(String uid) => _aura.watchAura(uid);
}

/// Historial paginado del ledger.
class GetAuraLedgerUseCase {
  /// Crea el caso de uso.
  const GetAuraLedgerUseCase(this._aura);

  final AuraRepository _aura;

  /// Devuelve una página de asientos, del más reciente al más viejo.
  Future<Result<Paginated<AuraEntry>>> call({
    required String uid,
    Object? cursor,
    int limit = 30,
  }) => _aura.getLedger(uid: uid, cursor: cursor, limit: limit);
}

/// Aura ganada por día, para el gráfico de evolución.
class GetDailyAuraUseCase {
  /// Crea el caso de uso.
  const GetDailyAuraUseCase(this._aura);

  final AuraRepository _aura;

  /// Devuelve un mapa `YYYY-MM-DD → aura`.
  Future<Result<Map<String, int>>> call({required String uid, int days = 30}) =>
      _aura.getDailyAura(uid: uid, days: days);
}

/// Tabla de niveles configurada en el servidor.
class GetAuraLevelsUseCase {
  /// Crea el caso de uso.
  const GetAuraLevelsUseCase(this._aura);

  final AuraRepository _aura;

  /// Devuelve los niveles ordenados por Aura mínima.
  Future<Result<List<AuraLevel>>> call() => _aura.getLevels();
}

/// Resumen de una serie diaria de Aura, para la pantalla de estadísticas.
///
/// Vive en el dominio y no en el widget para poder testear los casos límite
/// —serie vacía, todos en cero— sin montar una pantalla.
class AuraTrend {
  /// Crea el resumen.
  const AuraTrend({
    required this.byDay,
    required this.total,
    required this.bestDay,
    required this.activeDays,
  });

  /// Calcula el resumen a partir del mapa `YYYY-MM-DD → aura`.
  factory AuraTrend.from(Map<String, int> byDay) {
    final ordered = Map<String, int>.fromEntries(
      byDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );

    var total = 0;
    var best = 0;
    var active = 0;
    for (final amount in ordered.values) {
      total += amount;
      if (amount > best) {
        best = amount;
      }
      if (amount > 0) {
        active++;
      }
    }

    return AuraTrend(
      byDay: Map<String, int>.unmodifiable(ordered),
      total: total,
      bestDay: best,
      activeDays: active,
    );
  }

  /// Serie ordenada cronológicamente.
  final Map<String, int> byDay;

  /// Aura sumada en el período.
  final int total;

  /// Mejor día del período.
  final int bestDay;

  /// Días con al menos un punto de Aura.
  final int activeDays;

  /// Promedio por día del período, contando también los días en cero.
  ///
  /// Se incluyen los días vacíos a propósito: un promedio calculado solo sobre
  /// los días activos diría "40 por día" a quien entrenó dos veces en un mes.
  double get dailyAverage => byDay.isEmpty ? 0 : total / byDay.length;

  /// Altura relativa de un día respecto del mejor, entre 0.0 y 1.0.
  ///
  /// Es lo que necesita un gráfico de barras. Con todos los días en cero
  /// devuelve 0 en vez de dividir por cero.
  double heightFor(String day) {
    if (bestDay <= 0) {
      return 0;
    }
    return ((byDay[day] ?? 0) / bestDay).clamp(0.0, 1.0);
  }
}

/// Nivel siguiente al actual dentro de la tabla, o `null` si es el último.
AuraLevel? nextLevelAfter(List<AuraLevel> levels, int currentTotal) {
  final ordered = <AuraLevel>[...levels]
    ..sort((a, b) => a.minAura.compareTo(b.minAura));
  for (final level in ordered) {
    if (level.minAura > currentTotal) {
      return level;
    }
  }
  return null;
}
