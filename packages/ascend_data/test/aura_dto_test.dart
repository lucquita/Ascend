import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuraDto — saldo embebido en el perfil', () {
    test('mapea el saldo completo', () {
      final aura = AuraDto.auraFromUser(<String, dynamic>{
        'aura': <String, dynamic>{
          'total': 1840,
          'level': 7,
          'levelName': 'Constante',
          'xpInLevel': 140,
          'xpForNextLevel': 400,
        },
      });

      expect(aura.total, 1840);
      expect(aura.level, 7);
      expect(aura.levelName, 'Constante');
      expect(aura.levelProgress, closeTo(0.35, 0.0001));
      expect(aura.remainingForNextLevel, 260);
    });

    test('un perfil sin aura arranca en el nivel 1, no en cero', () {
      // Nivel 0 no existe: un documento a medio crear no puede mostrar a
      // alguien por debajo del mínimo.
      final aura = AuraDto.auraFromUser(const <String, dynamic>{});

      expect(aura.total, 0);
      expect(aura.level, 1);
      expect(aura.levelName, 'Iniciado');
      expect(aura.xpForNextLevel, 100);
    });

    test('tolera tipos equivocados', () {
      final aura = AuraDto.auraFromUser(<String, dynamic>{
        'aura': 'no soy un mapa',
      });

      expect(aura.level, 1);
      expect(aura.total, 0);
    });
  });

  group('AuraDto — asientos del ledger', () {
    test('mapea un asiento completo', () {
      final entry = AuraDto.entryFromMap(<String, dynamic>{
        'amount': 25,
        'balanceAfter': 1840,
        'reason': 'mission_completed',
        'ref': <String, dynamic>{'type': 'mission', 'id': 'mis_042'},
        'multiplier': 1.5,
        'note': 'Racha de 12 días ×1.5',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 14)),
      }, id: 'led_1');

      expect(entry.amount, 25);
      expect(entry.balanceAfter, 1840);
      expect(entry.reason, AuraReason.missionCompleted);
      expect(entry.refType, 'mission');
      expect(entry.refId, 'mis_042');
      expect(entry.multiplier, 1.5);
      expect(entry.isGain, isTrue);
    });

    test('un asiento negativo no se confunde con una ganancia', () {
      // Las penalizaciones y los ajustes de admin restan: el historial tiene
      // que poder distinguirlos.
      final entry = AuraDto.entryFromMap(<String, dynamic>{
        'amount': -50,
        'reason': 'penalty',
      }, id: 'led_2');

      expect(entry.amount, -50);
      expect(entry.isGain, isFalse);
      expect(entry.reason, AuraReason.penalty);
    });

    test('un motivo desconocido degrada sin romper el historial', () {
      final entry = AuraDto.entryFromMap(<String, dynamic>{
        'reason': 'motivo_del_futuro',
      }, id: 'led_3');

      expect(entry.reason, AuraReason.missionCompleted);
    });

    test('el multiplicador ausente vale 1, no 0', () {
      // Un multiplicador 0 haría creer que el asiento no otorgó nada.
      final entry = AuraDto.entryFromMap(
        const <String, dynamic>{},
        id: 'led_4',
      );

      expect(entry.multiplier, 1);
    });

    test('las fechas entran en UTC', () {
      final entry = AuraDto.entryFromMap(<String, dynamic>{
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 14)),
      }, id: 'led_5');

      expect(entry.createdAt.isUtc, isTrue);
    });
  });

  group('AuraDto — tabla de niveles', () {
    test('lee y ordena los niveles del catálogo', () {
      final levels = AuraDto.levelsFromConfig(<String, dynamic>{
        'levels': <Object?>[
          <String, dynamic>{'level': 3, 'name': 'Disciplinado', 'minAura': 300},
          <String, dynamic>{'level': 1, 'name': 'Iniciado', 'minAura': 0},
          <String, dynamic>{'level': 2, 'name': 'Aprendiz', 'minAura': 100},
        ],
      });

      expect(levels.map((l) => l.level), <int>[1, 2, 3]);
      expect(levels.first.name, 'Iniciado');
    });

    test('sin configuración devuelve vacío, no una tabla inventada', () {
      // Inventar una tabla que no coincida con la que usa el servidor para
      // calcular mostraría niveles que no corresponden con el saldo real.
      expect(AuraDto.levelsFromConfig(const <String, dynamic>{}), isEmpty);
      expect(
        AuraDto.levelsFromConfig(<String, dynamic>{'levels': 'roto'}),
        isEmpty,
      );
    });

    test('descarta entradas sin nombre', () {
      final levels = AuraDto.levelsFromConfig(<String, dynamic>{
        'levels': <Object?>[
          <String, dynamic>{'level': 1, 'name': 'Iniciado', 'minAura': 0},
          <String, dynamic>{'level': 2, 'minAura': 100},
          'ni siquiera es un mapa',
        ],
      });

      expect(levels, hasLength(1));
    });
  });
}
