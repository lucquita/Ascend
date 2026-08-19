import 'package:ascend_core/ascend_core.dart';
import 'package:test/test.dart';

void main() {
  _relativeLabelTests();

  group('AscendDateUtils — claves de día', () {
    test('toDayKey rellena mes y día con ceros', () {
      expect(AscendDateUtils.toDayKey(DateTime(2026, 8, 7)), '2026-08-07');
      expect(AscendDateUtils.toDayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('fromDayKey es la inversa de toDayKey', () {
      final date = DateTime(2026, 8, 7);
      expect(AscendDateUtils.fromDayKey(AscendDateUtils.toDayKey(date)), date);
    });

    test('fromDayKey devuelve null ante entradas corruptas', () {
      expect(AscendDateUtils.fromDayKey('no-es-fecha'), isNull);
      expect(AscendDateUtils.fromDayKey('2026-08'), isNull);
      expect(AscendDateUtils.fromDayKey(''), isNull);
    });
  });

  group('AscendDateUtils — comparaciones', () {
    test('la hora no afecta la comparación de días', () {
      final manana = DateTime(2026, 8, 7, 2);
      final noche = DateTime(2026, 8, 7, 23, 59);

      expect(AscendDateUtils.isSameDay(manana, noche), isTrue);
      expect(AscendDateUtils.daysBetween(manana, noche), 0);
    });

    test('daysBetween cuenta días completos', () {
      expect(
        AscendDateUtils.daysBetween(DateTime(2026, 8, 2), DateTime(2026, 8, 7)),
        5,
      );
    });

    test('isOverdue solo es cierto a partir del día siguiente', () {
      final hoy = DateTime(2026, 8, 7, 12);

      expect(
        AscendDateUtils.isOverdue(DateTime(2026, 8, 7, 1), now: hoy),
        isFalse,
      );
      expect(
        AscendDateUtils.isOverdue(DateTime(2026, 8, 6, 23), now: hoy),
        isTrue,
      );
    });
  });

  group('AscendDateUtils — rachas', () {
    // Esta es la regla que hace que alguien no pierda su racha por completar
    // una misión a las 23:50: el corte es por día local, no por 24 horas.
    test('sigue viva si la última actividad fue hoy', () {
      expect(
        AscendDateUtils.isStreakAlive(
          lastActivity: DateTime(2026, 8, 7, 0, 5),
          now: DateTime(2026, 8, 7, 23, 55),
        ),
        isTrue,
      );
    });

    test('sigue viva si la última actividad fue ayer', () {
      expect(
        AscendDateUtils.isStreakAlive(
          lastActivity: DateTime(2026, 8, 6, 23, 50),
          now: DateTime(2026, 8, 7, 0, 10),
        ),
        isTrue,
      );
    });

    test('se rompe a partir de dos días de inactividad', () {
      expect(
        AscendDateUtils.isStreakAlive(
          lastActivity: DateTime(2026, 8, 5, 23, 59),
          now: DateTime(2026, 8, 7),
        ),
        isFalse,
      );
    });
  });

  group('AscendDateUtils — semanas y rangos', () {
    test('startOfWeek devuelve el lunes', () {
      // 2026-08-07 es viernes.
      expect(
        AscendDateUtils.startOfWeek(DateTime(2026, 8, 7)),
        DateTime(2026, 8, 3),
      );
    });

    test('lastDayKeys devuelve el rango ordenado de más viejo a más nuevo', () {
      final keys = AscendDateUtils.lastDayKeys(3, now: DateTime(2026, 8, 7));

      expect(keys, <String>['2026-08-05', '2026-08-06', '2026-08-07']);
    });
  });
}

void _relativeLabelTests() {
  group('AscendDateUtils.relativeLabel', () {
    final now = DateTime.utc(2026, 8, 17, 12);

    test('menos de un minuto es "ahora"', () {
      expect(
        AscendDateUtils.relativeLabel(
          now.subtract(const Duration(seconds: 40)),
          now: now,
        ),
        'ahora',
      );
    });

    test('una fecha futura NO da un número negativo', () {
      // Pasa de verdad cuando el reloj del dispositivo va unos segundos
      // atrasado respecto del servidor, y "hace -1 m" es un error visible.
      expect(
        AscendDateUtils.relativeLabel(
          now.add(const Duration(minutes: 5)),
          now: now,
        ),
        'ahora',
      );
    });

    test('escala de minutos a horas, días y semanas', () {
      expect(
        AscendDateUtils.relativeLabel(
          now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        '5 m',
      );
      expect(
        AscendDateUtils.relativeLabel(
          now.subtract(const Duration(hours: 3)),
          now: now,
        ),
        '3 h',
      );
      expect(
        AscendDateUtils.relativeLabel(
          now.subtract(const Duration(days: 2)),
          now: now,
        ),
        '2 d',
      );
      expect(
        AscendDateUtils.relativeLabel(
          now.subtract(const Duration(days: 14)),
          now: now,
        ),
        '2 sem',
      );
    });

    test('más de un mes vuelve a la fecha', () {
      // "hace 14 semanas" ya no dice nada que se pueda ubicar en la cabeza.
      final old = now.subtract(const Duration(days: 100));
      expect(
        AscendDateUtils.relativeLabel(old, now: now),
        AscendDateUtils.toDayKey(old),
      );
    });
  });
}
