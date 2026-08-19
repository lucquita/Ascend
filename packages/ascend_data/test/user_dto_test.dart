import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Documento completo, tal como lo escribe `registerProfile`.
Map<String, dynamic> _completeDoc() => <String, dynamic>{
  'uid': 'u1',
  'email': 'ana@ascend.app',
  'displayName': 'Ana',
  'handle': 'ana',
  'photoUrl': 'https://cdn/a.jpg',
  'bio': 'Corriendo mi primer 10k',
  'role': 'user',
  'status': 'active',
  'locale': 'es',
  'aura': <String, dynamic>{
    'total': 1840,
    'level': 7,
    'levelName': 'Constante',
    'xpInLevel': 140,
    'xpForNextLevel': 400,
  },
  'stats': <String, dynamic>{
    'goalsActive': 3,
    'missionsCompleted': 128,
    'currentStreak': 12,
  },
  'settings': <String, dynamic>{
    'themeMode': 'dark',
    'timezone': 'America/Argentina/Buenos_Aires',
    'notifications': <String, dynamic>{'dailyReminder': false},
    'privacy': <String, dynamic>{'profileVisibility': 'public'},
  },
  'onboarding': <String, dynamic>{
    'completed': true,
    'interests': <String>['fitness', 'languages'],
  },
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8)),
  'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 7)),
};

void main() {
  group('UserDto — lectura', () {
    test('mapea un documento completo', () {
      final user = UserDto.fromMap(_completeDoc(), uid: 'u1');

      expect(user.uid, 'u1');
      expect(user.handle, 'ana');
      expect(user.displayHandle, '@ana');
      expect(user.aura.total, 1840);
      expect(user.aura.level, 7);
      expect(user.stats.currentStreak, 12);
      expect(user.settings.themeMode, 'dark');
      expect(user.settings.notifications.dailyReminder, isFalse);
      expect(user.onboardingCompleted, isTrue);
      expect(user.interests, <String>['fitness', 'languages']);
      expect(user.createdAt, DateTime.utc(2026, 8));
    });

    test('un documento vacío no rompe: cae a los valores por defecto', () {
      // Un perfil a medio escribir tiene que poder abrirse para arreglarlo, no
      // reventar la app.
      final user = UserDto.fromMap(const <String, dynamic>{}, uid: 'u1');

      expect(user.uid, 'u1');
      expect(user.handle, isEmpty);
      expect(user.hasProfile, isFalse);
      expect(user.aura.level, 1);
      expect(user.aura.total, 0);
      expect(user.status, UserStatus.active);
      expect(user.role, UserRole.user);
      expect(user.settings.timezone, 'America/Argentina/Buenos_Aires');
    });

    test('tolera campos con el tipo equivocado', () {
      final user = UserDto.fromMap(<String, dynamic>{
        'displayName': 42,
        'handle': <String>['no', 'soy', 'string'],
        'aura': 'esto tampoco es un mapa',
        'stats': 7,
        'onboarding': <String, dynamic>{'interests': 'ni esto'},
      }, uid: 'u1');

      expect(user.displayName, isEmpty);
      expect(user.handle, isEmpty);
      expect(user.aura.level, 1);
      expect(user.stats.missionsCompleted, 0);
      expect(user.interests, isEmpty);
    });

    test('acepta números en coma flotante donde espera enteros', () {
      // Firestore devuelve `double` si el valor se escribió con `increment()`.
      final user = UserDto.fromMap(<String, dynamic>{
        'aura': <String, dynamic>{'total': 1840.0, 'level': 7.0},
      }, uid: 'u1');

      expect(user.aura.total, 1840);
      expect(user.aura.level, 7);
    });

    test('un timestamp pendiente de servidor se lee como nulo, no falla', () {
      // Entre que se escribe con `serverTimestamp()` y que el servidor
      // confirma, la caché local devuelve null. No es un error.
      final user = UserDto.fromMap(<String, dynamic>{
        'updatedAt': null,
      }, uid: 'u1');

      expect(user.updatedAt, isNull);
      expect(user.createdAt, isNotNull);
    });
  });

  group('UserDto — seguridad del mapeo', () {
    test('el claim manda sobre el campo role del documento', () {
      // El documento es un espejo de conveniencia; la autoridad es el token.
      final doc = _completeDoc()..['role'] = 'admin';
      final user = UserDto.fromMap(
        doc,
        uid: 'u1',
        roleFromClaims: UserRole.user,
      );

      expect(
        user.role,
        UserRole.user,
        reason: 'un documento manipulado no puede otorgar permisos',
      );
      expect(user.isAdmin, isFalse);
    });

    test('un rol desconocido degrada a usuario, nunca a admin', () {
      final doc = _completeDoc()..['role'] = 'superadmin';
      final user = UserDto.fromMap(doc, uid: 'u1');

      expect(user.role, UserRole.user);
    });

    test('una visibilidad desconocida degrada a privada', () {
      final doc = _completeDoc();
      (doc['settings'] as Map<String, dynamic>)['privacy'] = <String, dynamic>{
        'profileVisibility': 'vaya-a-saber',
      };
      final user = UserDto.fromMap(doc, uid: 'u1');

      expect(user.settings.privacy.profileVisibility, Visibility.private);
    });

    test('una cuenta suspendida se refleja como tal', () {
      final doc = _completeDoc()..['status'] = 'suspended';
      final user = UserDto.fromMap(doc, uid: 'u1');

      expect(user.status, UserStatus.suspended);
      expect(user.canOperate, isFalse);
    });
  });

  group('UserDto — escritura', () {
    test('solo manda los campos que cambiaron', () {
      // Las reglas comparan el conjunto exacto de claves afectadas: un campo de
      // más hace fallar la escritura entera.
      final update = UserDto.profileUpdate(displayName: 'Ana G.');

      expect(update.keys, containsAll(<String>['displayName', 'updatedAt']));
      expect(update.containsKey('bio'), isFalse);
      expect(update.containsKey('photoUrl'), isFalse);
    });

    test('nunca incluye campos que el cliente no puede escribir', () {
      final update = UserDto.profileUpdate(
        displayName: 'Ana',
        bio: 'hola',
        photoUrl: 'https://cdn/a.jpg',
      );

      for (final forbidden in <String>[
        'aura',
        'stats',
        'role',
        'status',
        'handle',
        'email',
        'lastLoginAt',
      ]) {
        expect(
          update.containsKey(forbidden),
          isFalse,
          reason: '$forbidden lo escribe solo el servidor',
        );
      }
    });

    test('el cierre del onboarding manda completed y los intereses', () {
      final update = UserDto.onboardingUpdate(<String>['fitness']);
      final onboarding = update['onboarding']! as Map<String, Object?>;

      expect(onboarding['completed'], isTrue);
      expect(onboarding['interests'], <String>['fitness']);
    });

    test('los ajustes viajan completos y con el enum serializado', () {
      final update = UserDto.settingsUpdate(
        const UserSettings(
          themeMode: 'dark',
          privacy: PrivacySettings(profileVisibility: Visibility.followers),
        ),
      );
      final settings = update['settings']! as Map<String, Object?>;
      final privacy = settings['privacy']! as Map<String, Object?>;

      expect(settings['themeMode'], 'dark');
      expect(privacy['profileVisibility'], 'followers');
    });
  });
}
