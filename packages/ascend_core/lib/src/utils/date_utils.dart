/// Utilidades de fecha centradas en el cálculo de rachas.
///
/// Las rachas se calculan sobre el **día local de la persona**, no sobre UTC.
/// Alguien en Buenos Aires que completa una misión a las 22:00 no debe perder
/// la racha porque en UTC ya es el día siguiente. Por eso el día se representa
/// como `YYYY-MM-DD` en la zona horaria del usuario, y esa cadena es la que se
/// guarda en Firestore.
abstract final class AscendDateUtils {
  /// Convierte una fecha a su clave de día local (`2026-08-07`).
  static String toDayKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Reconstruye una fecha a partir de una clave de día. `null` si es inválida.
  static DateTime? fromDayKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day);
  }

  /// Medianoche del día de [date], descartando la hora.
  static DateTime startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Último instante del día de [date].
  static DateTime endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59, 999);

  /// Días completos entre dos fechas, ignorando la hora.
  static int daysBetween(DateTime from, DateTime to) =>
      startOfDay(to).difference(startOfDay(from)).inDays;

  /// `true` si ambas fechas caen el mismo día.
  static bool isSameDay(DateTime a, DateTime b) => daysBetween(a, b) == 0;

  /// `true` si [date] es hoy respecto de [now].
  static bool isToday(DateTime date, {DateTime? now}) =>
      isSameDay(date, now ?? DateTime.now());

  /// `true` si [date] ya pasó (día anterior a hoy).
  static bool isOverdue(DateTime date, {DateTime? now}) =>
      daysBetween(date, now ?? DateTime.now()) > 0;

  /// Decide si una racha sigue viva.
  ///
  /// Sigue viva si la última actividad fue hoy (0 días) o ayer (1 día). A
  /// partir de dos días de diferencia se rompe.
  static bool isStreakAlive({required DateTime lastActivity, DateTime? now}) {
    final diff = daysBetween(lastActivity, now ?? DateTime.now());
    return diff >= 0 && diff <= 1;
  }

  /// Lunes de la semana de [date].
  static DateTime startOfWeek(DateTime date) =>
      startOfDay(date).subtract(Duration(days: date.weekday - 1));

  /// Las claves de día de los últimos [days] días, de más antiguo a más nuevo.
  static List<String> lastDayKeys(int days, {DateTime? now}) {
    final today = startOfDay(now ?? DateTime.now());
    return List<String>.generate(
      days,
      (i) => toDayKey(today.subtract(Duration(days: days - 1 - i))),
    );
  }

  /// Etiqueta relativa corta: `ahora`, `5 m`, `3 h`, `2 d`, `4 sem`.
  ///
  /// Se usa en listas donde la antigüedad importa más que el momento exacto —una
  /// bandeja de notificaciones, un feed—. Ahí "hace 3 h" se entiende de un
  /// vistazo y una fecha completa obliga a hacer la cuenta.
  ///
  /// Por encima de un mes vuelve a la fecha: "hace 14 semanas" ya no dice nada
  /// que se pueda ubicar en la cabeza.
  ///
  /// Una fecha futura devuelve `ahora` en lugar de un número negativo: pasa de
  /// verdad cuando el reloj del dispositivo va unos segundos atrasado respecto
  /// del servidor, y "hace -1 m" es un error visible.
  static String relativeLabel(DateTime date, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final elapsed = reference.difference(date);

    if (elapsed.isNegative || elapsed.inMinutes < 1) {
      return 'ahora';
    }
    if (elapsed.inHours < 1) {
      return '${elapsed.inMinutes} m';
    }
    if (elapsed.inDays < 1) {
      return '${elapsed.inHours} h';
    }
    if (elapsed.inDays < 7) {
      return '${elapsed.inDays} d';
    }
    if (elapsed.inDays < 30) {
      return '${elapsed.inDays ~/ 7} sem';
    }
    return toDayKey(date);
  }
}
