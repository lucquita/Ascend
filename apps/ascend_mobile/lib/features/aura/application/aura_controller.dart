import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/auth/application/session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Saldo y nivel de Aura, en vivo.
///
/// Se observa por streaming porque el saldo lo cambia el **servidor**: al
/// completar una misión, el trigger escribe el nuevo total y esta pantalla se
/// entera sola. Con una lectura puntual habría que refrescar a mano y la
/// celebración llegaría tarde o nunca.
final StreamProvider<Result<Aura>> auraProvider = StreamProvider<Result<Aura>>((
  ref,
) {
  final uid = ref.watch(currentUserProvider)?.uid;
  if (uid == null) {
    return Stream<Result<Aura>>.value(_noSession<Aura>());
  }
  return ref.watch(watchAuraUseCaseProvider).call(uid);
}, name: 'aura');

/// Primera página del ledger.
///
/// `FutureProvider` y no `StreamProvider`: el historial es un registro contable
/// append-only que se consulta, no un dato que la pantalla necesite ver mutar en
/// vivo. Mantener una suscripción abierta costaría lecturas sin aportar nada.
final FutureProvider<Result<Paginated<AuraEntry>>> auraLedgerProvider =
    FutureProvider<Result<Paginated<AuraEntry>>>((ref) async {
      final uid = ref.watch(currentUserProvider)?.uid;
      if (uid == null) {
        return _noSession<Paginated<AuraEntry>>();
      }
      return ref.watch(getAuraLedgerUseCaseProvider).call(uid: uid);
    }, name: 'auraLedger');

/// Evolución diaria de los últimos 30 días, ya resumida.
final FutureProvider<Result<AuraTrend>> auraTrendProvider =
    FutureProvider<Result<AuraTrend>>((ref) async {
      final uid = ref.watch(currentUserProvider)?.uid;
      if (uid == null) {
        return _noSession<AuraTrend>();
      }
      final result = await ref
          .watch(getDailyAuraUseCaseProvider)
          .call(uid: uid);
      return result.map(AuraTrend.from);
    }, name: 'auraTrend');

/// Tabla de niveles configurada en el servidor.
final FutureProvider<Result<List<AuraLevel>>> auraLevelsProvider =
    FutureProvider<Result<List<AuraLevel>>>(
      (ref) => ref.watch(getAuraLevelsUseCaseProvider).call(),
      name: 'auraLevels',
    );

// Sin `const`: Dart no admite un parámetro de tipo como argumento de tipo en
// una expresión constante.
Result<T> _noSession<T>() => Failed<T>(_sessionExpired);

const AuthFailure _sessionExpired = AuthFailure(
  messageKey: 'failure.auth.sessionExpired',
  code: 'no-session',
);
