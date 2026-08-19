import 'package:ascend_domain/ascend_domain.dart';
import 'package:test/test.dart';

Mission _mission({
  MissionStatus status = MissionStatus.pending,
  bool requiresEvidence = false,
  Evidence? evidence,
  DateTime? dueDate,
}) => Mission(
  id: 'm1',
  ownerId: 'u1',
  goalId: 'g1',
  title: 'Leer 20 páginas',
  createdAt: DateTime(2026, 8, 2),
  status: status,
  requiresEvidence: requiresEvidence,
  evidence: evidence,
  dueDate: dueDate,
);

void main() {
  group('Mission.canComplete — la regla que protege el sistema de Aura', () {
    test('una misión pendiente sin exigencias se puede completar', () {
      expect(_mission().canComplete, isTrue);
    });

    test('una misión ya completada NO se puede volver a completar', () {
      // Sin esta regla, completar dos veces la misma misión duplicaría el Aura.
      expect(_mission(status: MissionStatus.completed).canComplete, isFalse);
    });

    test('una misión vencida o salteada tampoco', () {
      expect(_mission(status: MissionStatus.expired).canComplete, isFalse);
      expect(_mission(status: MissionStatus.skipped).canComplete, isFalse);
    });

    test('si exige evidencia y no hay imagen, no se puede completar', () {
      expect(_mission(requiresEvidence: true).canComplete, isFalse);
      expect(
        _mission(
          requiresEvidence: true,
          evidence: Evidence(
            capturedAt: DateTime(2026, 8, 7),
            note: 'sin foto',
          ),
        ).canComplete,
        isFalse,
      );
    });

    test('una evidencia solo local ya habilita completar (flujo offline)', () {
      // Es lo que permite terminar una misión en modo avión: la foto viaja
      // después, pero la misión se cierra en el momento.
      expect(
        _mission(
          requiresEvidence: true,
          evidence: Evidence(
            capturedAt: DateTime(2026, 8, 7),
            localPath: '/tmp/foto.jpg',
          ),
        ).canComplete,
        isTrue,
      );
    });
  });

  group('Mission — vencimiento', () {
    test('isOverdue solo aplica a misiones abiertas', () {
      final vencida = _mission(dueDate: DateTime(2026, 8, 2));
      final completada = _mission(
        status: MissionStatus.completed,
        dueDate: DateTime(2026, 8, 2),
      );

      expect(vencida.isOverdue(now: DateTime(2026, 8, 7)), isTrue);
      expect(completada.isOverdue(now: DateTime(2026, 8, 7)), isFalse);
    });

    test('una misión sin fecha límite nunca vence', () {
      expect(_mission().isOverdue(now: DateTime(2030)), isFalse);
    });

    test('isDueToday ignora la hora', () {
      final m = _mission(dueDate: DateTime(2026, 8, 7, 23, 30));
      expect(m.isDueToday(now: DateTime(2026, 8, 7, 6)), isTrue);
    });
  });

  group('GoalProgress', () {
    test('un objetivo sin misiones está en 0 y no se considera completo', () {
      const progress = GoalProgress.empty;
      expect(progress.fraction, 0);
      expect(progress.isComplete, isFalse);
    });

    test('calcula la fracción y el porcentaje', () {
      const progress = GoalProgress(missionsTotal: 24, missionsCompleted: 9);
      expect(progress.fraction, closeTo(0.375, 0.0001));
      expect(progress.percent, closeTo(37.5, 0.0001));
      expect(progress.remaining, 15);
    });

    test('se satura en 1.0 aunque los datos vengan inconsistentes', () {
      const progress = GoalProgress(missionsTotal: 5, missionsCompleted: 9);
      expect(progress.fraction, 1.0);
      expect(progress.isComplete, isTrue);
    });
  });

  group('Aura', () {
    test('el progreso de nivel se mantiene entre 0 y 1', () {
      const aura = Aura(
        total: 1840,
        level: 7,
        levelName: 'Constante',
        xpInLevel: 140,
        xpForNextLevel: 400,
      );

      expect(aura.levelProgress, closeTo(0.35, 0.0001));
      expect(aura.remainingForNextLevel, 260);
    });

    test('no divide por cero cuando no hay siguiente nivel', () {
      const aura = Aura(
        total: 99999,
        level: 15,
        levelName: 'Ascendido',
        xpInLevel: 0,
        xpForNextLevel: 0,
      );

      expect(aura.levelProgress, 1.0);
      expect(aura.remainingForNextLevel, 0);
    });
  });

  group('Enums — tolerancia a valores desconocidos', () {
    // Si el backend agrega un valor nuevo, las versiones viejas de la app deben
    // degradarlo, no romperse en las manos del usuario.
    test('un estado desconocido cae en el valor por defecto', () {
      expect(GoalStatus.fromWire('inventado'), GoalStatus.active);
      expect(MissionStatus.fromWire(null), MissionStatus.pending);
      expect(ModerationStatus.fromWire('???'), ModerationStatus.visible);
    });

    test('un rol desconocido NUNCA concede permisos de administrador', () {
      expect(UserRole.fromWire('superadmin'), UserRole.user);
      expect(UserRole.fromWire(null), UserRole.user);
      expect(UserRole.fromWire('admin'), UserRole.admin);
    });

    test('una visibilidad desconocida cae en el valor más restrictivo', () {
      expect(Visibility.fromWire('lo-que-sea'), Visibility.private);
      expect(Visibility.fromWire('public'), Visibility.public);
    });

    test('el ida y vuelta por wireValue es estable', () {
      for (final status in MissionStatus.values) {
        expect(MissionStatus.fromWire(status.wireValue), status);
      }
      for (final reason in AuraReason.values) {
        expect(AuraReason.fromWire(reason.wireValue), reason);
      }
    });
  });

  group('PostType — la premisa del producto como regla de dominio', () {
    test('los logros exigen referenciar algo real; la reflexión no', () {
      expect(PostType.missionCompleted.requiresSource, isTrue);
      expect(PostType.goalCompleted.requiresSource, isTrue);
      expect(PostType.milestone.requiresSource, isTrue);
      expect(PostType.reflection.requiresSource, isFalse);
    });
  });

  group('AppUser', () {
    test('expone el handle listo para mostrar', () {
      final user = AppUser(
        uid: 'u1',
        email: 'a@b.com',
        displayName: 'Santino',
        handle: 'santino',
        createdAt: DateTime(2026),
      );

      expect(user.displayHandle, '@santino');
      expect(user.canOperate, isTrue);
      expect(user.isAdmin, isFalse);
    });

    test('una cuenta suspendida no puede operar', () {
      final user = AppUser(
        uid: 'u1',
        email: 'a@b.com',
        displayName: 'Santino',
        handle: 'santino',
        createdAt: DateTime(2026),
        status: UserStatus.suspended,
      );

      expect(user.canOperate, isFalse);
    });

    test('copyWith preserva uid y createdAt', () {
      final user = AppUser(
        uid: 'u1',
        email: 'a@b.com',
        displayName: 'Santino',
        handle: 'santino',
        createdAt: DateTime(2026),
      );
      final updated = user.copyWith(displayName: 'Santi');

      expect(updated.uid, 'u1');
      expect(updated.createdAt, DateTime(2026));
      expect(updated.displayName, 'Santi');
      expect(updated, user, reason: 'La identidad la define el uid.');
    });
  });
}
