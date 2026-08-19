import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/src/dtos/admin_dto.dart';
import 'package:ascend_data/src/dtos/category_dto.dart';
import 'package:ascend_data/src/dtos/post_dto.dart';
import 'package:ascend_data/src/dtos/user_dto.dart';
import 'package:ascend_data/src/mappers/error_mapper.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctions;

/// Implementación de [AdminRepository] sobre Firestore y Cloud Functions.
///
/// ## Lecturas por Firestore, escrituras por Functions
///
/// Las lecturas van directas porque las reglas ya las restringen a `isAdmin()`
/// y pasar por una función solo sumaría latencia y costo.
///
/// Las escrituras **no**, aunque las reglas se lo permitirían al admin. El
/// motivo es `auditLog`: es inescribible desde cualquier cliente, así que la
/// única forma de garantizar que toda acción administrativa quede registrada es
/// que la acción y su registro ocurran en la misma transacción del servidor. Si
/// el panel escribiera por su cuenta, existiría siempre el caso de la acción
/// aplicada sin rastro de quién la hizo.
class AdminRepositoryImpl implements AdminRepository {
  /// Crea el repositorio.
  const AdminRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : _firestore = firestore,
       _functions = functions;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Stream<Result<AdminStats>> watchStats() => guardStream(
    // Un único documento: el dashboard no recorre colecciones. Ver
    // `aggregate-stats.ts` para el porqué.
    _firestore
        .collection('adminStats')
        .doc('latest')
        .snapshots()
        .map(AdminStatsDto.fromFirestore),
  );

  @override
  Future<Result<Paginated<AppUser>>> listUsers({
    Object? cursor,
    int limit = 25,
  }) => runGuarded(() async {
    var query = _firestore
        .collection('users')
        .orderBy('createdAt', descending: true)
        .limit(limit + 1);

    if (cursor is DocumentSnapshot) {
      query = query.startAfterDocument(cursor);
    }

    final snapshot = await query.get();
    // Se pide uno de más para saber si hay página siguiente sin una consulta
    // extra: si volvieron `limit + 1`, hay más.
    final hasMore = snapshot.docs.length > limit;
    final docs = hasMore ? snapshot.docs.take(limit).toList() : snapshot.docs;

    return Paginated<AppUser>(
      items: <AppUser>[
        // El rol se lee del documento, no del claim: desde el panel no hay
        // forma de inspeccionar el token de otra persona. `setUserRole` mantiene
        // el campo como espejo justamente para esto (ADR-004).
        for (final doc in docs) UserDto.fromFirestore(doc),
      ],
      cursor: docs.isEmpty ? null : docs.last,
      hasMore: hasMore,
    );
  });

  @override
  Stream<Result<List<Report>>> watchOpenReports({int limit = 50}) =>
      guardStream(
        _firestore
            .collection('reports')
            .where('status', whereIn: <String>['open', 'reviewing'])
            .orderBy('createdAt')
            .limit(limit)
            .snapshots()
            .map(
              (snapshot) => sortModerationQueue(<Report>[
                for (final doc in snapshot.docs) ReportDto.fromFirestore(doc),
              ]),
            ),
      );

  @override
  Stream<Result<List<AuditEntry>>> watchAuditLog({int limit = 100}) =>
      guardStream(
        _firestore
            .collection('auditLog')
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .snapshots()
            .map(
              (snapshot) => <AuditEntry>[
                for (final doc in snapshot.docs)
                  AuditEntryDto.fromFirestore(doc),
              ],
            ),
      );

  @override
  Future<Result<void>> setUserRole({
    required String targetUid,
    required UserRole role,
    String? reason,
  }) => runGuarded(() async {
    await _functions.httpsCallable('setUserRole').call<Object?>(
      <String, Object?>{
        'targetUid': targetUid,
        'role': role.wireValue,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  });

  @override
  Future<Result<void>> setUserStatus({
    required String targetUid,
    required UserStatus status,
    String? reason,
  }) => runGuarded(() async {
    await _functions.httpsCallable('setUserStatus').call<Object?>(
      <String, Object?>{
        'targetUid': targetUid,
        'status': status.wireValue,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  });

  @override
  Future<Result<void>> resolveReport({
    required String reportId,
    required ModerationAction action,
    String? note,
  }) => runGuarded(() async {
    await _functions
        .httpsCallable('moderateContent')
        .call<Object?>(<String, Object?>{
          'reportId': reportId,
          'action': action.wireValue,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        });
  });

  @override
  Future<Result<void>> saveCategory(Category category) => runGuarded(() async {
    // El catálogo sí se escribe directo: no hay nada que auditar más allá del
    // propio documento, que queda con su historial en Firestore, y pasar por
    // una función solo agregaría una pieza más que puede fallar.
    await _firestore
        .collection('categories')
        .doc(category.id)
        .set(CategoryWriteDto.toWrite(category), SetOptions(merge: true));
  });
}
