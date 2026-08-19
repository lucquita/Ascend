import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:test/test.dart';

class _FakeAdminRepository implements AdminRepository {
  UserRole? roleSet;
  UserStatus? statusSet;
  String? lastReason;
  ModerationAction? resolvedWith;
  int calls = 0;
  Failure? failure;

  @override
  Future<Result<void>> setUserRole({
    required String targetUid,
    required UserRole role,
    String? reason,
  }) async {
    calls++;
    roleSet = role;
    lastReason = reason;
    return failure == null ? const Success<void>(null) : Failed<void>(failure!);
  }

  @override
  Future<Result<void>> setUserStatus({
    required String targetUid,
    required UserStatus status,
    String? reason,
  }) async {
    calls++;
    statusSet = status;
    lastReason = reason;
    return failure == null ? const Success<void>(null) : Failed<void>(failure!);
  }

  @override
  Future<Result<void>> resolveReport({
    required String reportId,
    required ModerationAction action,
    String? note,
  }) async {
    calls++;
    resolvedWith = action;
    lastReason = note;
    return failure == null ? const Success<void>(null) : Failed<void>(failure!);
  }

  @override
  Future<Result<void>> saveCategory(Category category) async {
    calls++;
    return const Success<void>(null);
  }

  @override
  Stream<Result<AdminStats>> watchStats() =>
      const Stream<Result<AdminStats>>.empty();

  @override
  Future<Result<Paginated<AppUser>>> listUsers({
    Object? cursor,
    int limit = 25,
  }) => throw UnimplementedError();

  @override
  Stream<Result<List<Report>>> watchOpenReports({int limit = 50}) =>
      const Stream<Result<List<Report>>>.empty();

  @override
  Stream<Result<List<AuditEntry>>> watchAuditLog({int limit = 100}) =>
      const Stream<Result<List<AuditEntry>>>.empty();
}

AppUser _user({
  String uid = 'u1',
  String name = 'Ana Pérez',
  String handle = 'ana',
  String email = 'ana@ascend.app',
  UserRole role = UserRole.user,
  UserStatus status = UserStatus.active,
}) => AppUser(
  uid: uid,
  email: email,
  displayName: name,
  handle: handle,
  createdAt: DateTime.utc(2026),
  role: role,
  status: status,
);

Report _report({
  String id = 'r1',
  ReportReason reason = ReportReason.spam,
  int daysAgo = 0,
}) => Report(
  id: id,
  reporterId: 'u9',
  targetType: 'post',
  targetId: 'p1',
  reason: reason,
  createdAt: DateTime.utc(2026, 8, 17).subtract(Duration(days: daysAgo)),
);

void main() {
  group('matchesAdminFilter', () {
    test('sin filtro pasa todo el mundo', () {
      expect(matchesAdminFilter(_user(), const AdminUserFilter()), isTrue);
    });

    test('busca por nombre, handle y email sin importar mayúsculas', () {
      final user = _user();
      for (final query in <String>['PÉREZ', 'ana', 'ASCEND.APP']) {
        expect(
          matchesAdminFilter(user, AdminUserFilter(query: query)),
          isTrue,
          reason: 'debería encontrar con "$query"',
        );
      }
    });

    test('el uid coincide entero, no como fragmento', () {
      // Un uid es opaco: un fragmento coincidiría con cuentas al azar y quien
      // busca creería haber encontrado a la persona equivocada.
      final user = _user(uid: 'abc123');
      expect(
        matchesAdminFilter(user, const AdminUserFilter(query: 'abc123')),
        isTrue,
      );
      expect(
        matchesAdminFilter(user, const AdminUserFilter(query: 'abc')),
        isFalse,
      );
    });

    test('filtra por rol y por estado', () {
      final admin = _user(role: UserRole.admin);
      expect(
        matchesAdminFilter(admin, const AdminUserFilter(role: UserRole.admin)),
        isTrue,
      );
      expect(
        matchesAdminFilter(admin, const AdminUserFilter(role: UserRole.user)),
        isFalse,
      );
      expect(
        matchesAdminFilter(
          _user(status: UserStatus.suspended),
          const AdminUserFilter(status: UserStatus.suspended),
        ),
        isTrue,
      );
    });

    test('los filtros se combinan con Y, no con O', () {
      // Con O, filtrar "admins suspendidos" traería también a los admins
      // activos y quien modera actuaría sobre la cuenta equivocada.
      final admin = _user(role: UserRole.admin);
      expect(
        matchesAdminFilter(
          admin,
          const AdminUserFilter(
            role: UserRole.admin,
            status: UserStatus.suspended,
          ),
        ),
        isFalse,
      );
    });

    test('copyWith puede volver a "todos"', () {
      // Con `role ?? this.role` no habría forma: pasar null significaría "no lo
      // cambies" y el filtro quedaría pegado para siempre.
      const filter = AdminUserFilter(
        role: UserRole.admin,
        status: UserStatus.suspended,
      );
      expect(filter.copyWith(clearRole: true).role, isNull);
      expect(filter.copyWith(clearStatus: true).status, isNull);
      expect(filter.copyWith(clearRole: true).status, UserStatus.suspended);
    });
  });

  group('sortModerationQueue', () {
    test('lo grave va primero, aunque haya llegado después', () {
      // Una bandeja cronológica hace que un caso de violencia espere detrás de
      // veinte reportes de spam.
      final queue = sortModerationQueue(<Report>[
        _report(id: 'spam', daysAgo: 10),
        _report(id: 'violencia', reason: ReportReason.violence),
        _report(id: 'acoso', reason: ReportReason.harassment, daysAgo: 3),
      ]);

      expect(queue.map((Report r) => r.id).toList(), <String>[
        'violencia',
        'acoso',
        'spam',
      ]);
    });

    test('a igual gravedad, primero lo más viejo', () {
      // Un reporte que lleva días esperando es alguien a quien ya le fallamos.
      final queue = sortModerationQueue(<Report>[
        _report(id: 'nuevo'),
        _report(id: 'viejo', daysAgo: 5),
      ]);

      expect(queue.first.id, 'viejo');
    });

    test('no muta la lista que recibe', () {
      // Ordenar en el lugar rompería la lista que Firestore mantiene viva.
      final original = <Report>[
        _report(id: 'spam'),
        _report(id: 'violencia', reason: ReportReason.violence),
      ];
      sortModerationQueue(original);
      expect(original.first.id, 'spam');
    });

    test('una lista vacía no rompe', () {
      expect(sortModerationQueue(<Report>[]), isEmpty);
    });
  });

  group('SetUserRoleUseCase', () {
    late _FakeAdminRepository admin;

    setUp(() => admin = _FakeAdminRepository());

    test('cambia el rol de otra persona', () async {
      final result = await SetUserRoleUseCase(
        admin,
      ).call(actorUid: 'admin1', targetUid: 'u2', role: UserRole.admin);

      expect(result.isSuccess, isTrue);
      expect(admin.roleSet, UserRole.admin);
    });

    test('no deja cambiarse el rol a uno mismo', () async {
      // Quitarse el admin por error un viernes deja el panel sin quien lo
      // administre: recuperarlo exigiría un script con credenciales de
      // servicio.
      final result = await SetUserRoleUseCase(
        admin,
      ).call(actorUid: 'admin1', targetUid: 'admin1', role: UserRole.user);

      expect(
        result.failureOrNull?.messageKey,
        'validation.admin.selfRoleChange',
      );
      expect(admin.calls, 0, reason: 'no debería llegar a la red');
    });

    test('propaga el fallo del servidor', () async {
      admin.failure = const PermissionFailure();

      final result = await SetUserRoleUseCase(
        admin,
      ).call(actorUid: 'admin1', targetUid: 'u2', role: UserRole.admin);

      expect(result.failureOrNull, isA<PermissionFailure>());
    });
  });

  group('SetUserStatusUseCase', () {
    late _FakeAdminRepository admin;

    setUp(() => admin = _FakeAdminRepository());

    test('suspende con motivo', () async {
      final result = await SetUserStatusUseCase(admin).call(
        actorUid: 'admin1',
        targetUid: 'u2',
        status: UserStatus.suspended,
        reason: 'Acoso reiterado',
      );

      expect(result.isSuccess, isTrue);
      expect(admin.statusSet, UserStatus.suspended);
      expect(admin.lastReason, 'Acoso reiterado');
    });

    test('sin motivo no suspende', () async {
      // Una suspensión sin motivo es una decisión que después nadie puede
      // revisar, ni siquiera quien la tomó.
      final result = await SetUserStatusUseCase(
        admin,
      ).call(actorUid: 'admin1', targetUid: 'u2', status: UserStatus.suspended);

      expect(
        result.failureOrNull?.messageKey,
        'validation.admin.reasonRequired',
      );
      expect(admin.calls, 0);
    });

    test('un motivo de relleno tampoco alcanza', () async {
      final result = await SetUserStatusUseCase(admin).call(
        actorUid: 'admin1',
        targetUid: 'u2',
        status: UserStatus.suspended,
        reason: '  x ',
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('reactivar no exige motivo: es la acción que repara', () async {
      final result = await SetUserStatusUseCase(
        admin,
      ).call(actorUid: 'admin1', targetUid: 'u2', status: UserStatus.active);

      expect(result.isSuccess, isTrue);
      expect(admin.statusSet, UserStatus.active);
    });

    test('no deja suspenderse a uno mismo', () async {
      final result = await SetUserStatusUseCase(admin).call(
        actorUid: 'admin1',
        targetUid: 'admin1',
        status: UserStatus.suspended,
        reason: 'un motivo válido',
      );

      expect(
        result.failureOrNull?.messageKey,
        'validation.admin.selfStatusChange',
      );
      expect(admin.calls, 0);
    });
  });

  group('ResolveReportUseCase', () {
    late _FakeAdminRepository admin;

    setUp(() => admin = _FakeAdminRepository());

    test('descartar no necesita nota', () async {
      final result = await ResolveReportUseCase(
        admin,
      ).call(reportId: 'r1', action: ModerationAction.dismiss);

      expect(result.isSuccess, isTrue);
      expect(admin.resolvedWith, ModerationAction.dismiss);
    });

    test('suspender al autor sí la necesita', () async {
      final result = await ResolveReportUseCase(
        admin,
      ).call(reportId: 'r1', action: ModerationAction.suspendAuthor);

      expect(
        result.failureOrNull?.messageKey,
        'validation.admin.reasonRequired',
      );
      expect(admin.calls, 0);
    });

    test('sin reporte no hace nada', () async {
      final result = await ResolveReportUseCase(
        admin,
      ).call(reportId: '   ', action: ModerationAction.dismiss);

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(admin.calls, 0);
    });
  });

  group('AdminStats', () {
    final now = DateTime.utc(2026, 8, 17, 12);

    test('reconoce métricas viejas', () {
      // Mostrar números de hace una semana como si fueran de hoy es peor que
      // no mostrar nada: alguien toma una decisión con ellos.
      final stale = AdminStats(
        generatedAt: now.subtract(const Duration(hours: 72)),
      );
      expect(stale.isStaleAt(now), isTrue);
    });

    test('las de esta madrugada no son viejas', () {
      final fresh = AdminStats(
        generatedAt: now.subtract(const Duration(hours: 8)),
      );
      expect(fresh.isStaleAt(now), isFalse);
    });

    test('un documento nunca escrito queda marcado como viejo', () {
      final never = AdminStats(
        generatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      expect(never.isStaleAt(now), isTrue);
    });
  });

  group('exportaciones', () {
    test('el CSV de usuarios lleva una fila por persona más el encabezado', () {
      final csv = usersToCsv(<AppUser>[_user(), _user(uid: 'u2')]);
      expect('\r\n'.allMatches(csv).length, 3);
      expect(csv, startsWith('uid,handle,nombre,email,rol,estado'));
    });

    test('un nombre con coma no rompe las columnas', () {
      final csv = usersToCsv(<AppUser>[_user(name: 'Pérez, Ana')]);
      expect(csv, contains('"Pérez, Ana"'));
    });

    test('el CSV de auditoría incluye el detalle de la acción', () {
      final csv = auditToCsv(<AuditEntry>[
        AuditEntry(
          id: 'a1',
          action: 'set_user_role',
          actorUid: 'admin1',
          targetUid: 'u2',
          createdAt: DateTime.utc(2026, 8, 17),
          details: const <String, Object?>{'newRole': 'admin'},
        ),
      ]);

      expect(csv, contains('set_user_role'));
      expect(csv, contains('newRole'));
    });
  });

  group('AuditEntry', () {
    test('traduce las acciones conocidas', () {
      expect(
        AuditEntry(
          id: 'a',
          action: 'set_user_role',
          actorUid: 'x',
          createdAt: DateTime.utc(2026),
        ).actionLabel,
        'Cambio de rol',
      );
    });

    test('una acción desconocida se muestra tal cual, no se oculta', () {
      // Una auditoría que esconde lo que no reconoce deja de servir para
      // auditar justo cuando aparece algo nuevo.
      expect(
        AuditEntry(
          id: 'a',
          action: 'accion_futura',
          actorUid: 'x',
          createdAt: DateTime.utc(2026),
        ).actionLabel,
        'accion_futura',
      );
    });
  });

  group('ModerationAction', () {
    test('solo suspender pide confirmación', () {
      expect(ModerationAction.suspendAuthor.needsConfirmation, isTrue);
      expect(ModerationAction.hideContent.needsConfirmation, isFalse);
      expect(ModerationAction.dismiss.needsConfirmation, isFalse);
    });

    test('los valores que viajan coinciden con los del servidor', () {
      // Si se desincronizan, la llamable rechaza la acción con un
      // `invalid-argument` que no dice nada útil.
      expect(ModerationAction.hideContent.wireValue, 'hide_content');
      expect(ModerationAction.dismiss.wireValue, 'dismiss');
      expect(ModerationAction.suspendAuthor.wireValue, 'suspend_author');
    });
  });
}
