import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/src/datasources/remote/firestore_aura_datasource.dart';
import 'package:ascend_data/src/dtos/aura_dto.dart';
import 'package:ascend_data/src/mappers/error_mapper.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Implementación de [AuraRepository]. Solo lectura, por diseño.
class AuraRepositoryImpl implements AuraRepository {
  /// Crea el repositorio.
  const AuraRepositoryImpl({required FirestoreAuraDataSource auraDataSource})
    : _aura = auraDataSource;

  final FirestoreAuraDataSource _aura;

  @override
  Stream<Result<Aura>> watchAura(String uid) {
    return guardStream(_aura.watchUser(uid)).map(
      (result) => result.flatMap((snapshot) {
        if (!snapshot.exists) {
          return const Failed<Aura>(NotFoundFailure(code: 'profile-missing'));
        }
        return Success<Aura>(
          AuraDto.auraFromUser(snapshot.data() ?? const <String, dynamic>{}),
        );
      }),
    );
  }

  @override
  Future<Result<Paginated<AuraEntry>>> getLedger({
    required String uid,
    Object? cursor,
    int limit = 30,
  }) => runGuarded(() async {
    final snapshot = await _aura.getLedger(
      uid: uid,
      cursor: cursor is DocumentSnapshot<Map<String, dynamic>> ? cursor : null,
      limit: limit,
    );

    return Paginated<AuraEntry>(
      items: snapshot.docs
          .map(AuraDto.entryFromFirestore)
          .toList(growable: false),
      cursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  });

  @override
  Future<Result<Map<String, int>>> getDailyAura({
    required String uid,
    int days = 30,
  }) => runGuarded(() async {
    final snapshot = await _aura.getRecentEntries(uid: uid, days: days);

    // Se agrega en el cliente y no en el servidor porque son pocos documentos
    // —un mes de asientos— y evitarlo exigiría un agregado diario mantenido por
    // otra Function. Si el volumen crece, ese es el momento de moverlo.
    final byDay = <String, int>{};
    for (final doc in snapshot.docs) {
      final entry = AuraDto.entryFromFirestore(doc);
      final key = AscendDateUtils.toDayKey(entry.createdAt);
      byDay[key] = (byDay[key] ?? 0) + entry.amount;
    }
    return Map<String, int>.unmodifiable(byDay);
  });

  @override
  Future<Result<List<AuraLevel>>> getLevels() => runGuarded(() async {
    final snapshot = await _aura.getAuraRules();
    if (!snapshot.exists) {
      // Sin documento, el servidor usa sus valores por defecto y el cliente no
      // los conoce. Devolver una lista vacía es más honesto que inventar una
      // tabla que podría no coincidir con la que calcula las recompensas.
      return const <AuraLevel>[];
    }
    return AuraDto.levelsFromConfig(
      snapshot.data() ?? const <String, dynamic>{},
    );
  });
}
