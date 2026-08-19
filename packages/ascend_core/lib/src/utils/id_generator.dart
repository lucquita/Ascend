import 'dart:math';

/// Genera identificadores en el cliente.
///
/// Ascend crea los IDs antes de escribir, no después. Eso vuelve idempotentes
/// las escrituras: si se pierde la conexión y se reintenta, el documento se
/// sobrescribe en lugar de duplicarse. Es la base del funcionamiento offline.
abstract final class IdGenerator {
  static const String _alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  static final Random _random = Random.secure();

  /// Genera un ID compatible con Firestore (20 caracteres, como los del SDK).
  static String generate() {
    final buffer = StringBuffer();
    for (var i = 0; i < 20; i++) {
      buffer.write(_alphabet[_random.nextInt(_alphabet.length)]);
    }
    return buffer.toString();
  }

  /// Genera un ID ordenable cronológicamente.
  ///
  /// Antepone el timestamp en base 36, de modo que el orden lexicográfico
  /// coincide con el cronológico. Útil para claves de cola local donde
  /// queremos procesar en orden de llegada sin leer el contenido.
  static String generateSortable({DateTime? now}) {
    final millis = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    final prefix = millis.toRadixString(36).padLeft(9, '0');
    final buffer = StringBuffer(prefix);
    for (var i = 0; i < 11; i++) {
      buffer.write(_alphabet[_random.nextInt(_alphabet.length)]);
    }
    return buffer.toString();
  }

  /// ID determinístico para documentos que deben ser únicos por par de claves.
  ///
  /// Por ejemplo un reporte: `{targetId}_{reporterId}` impide que la misma
  /// persona reporte dos veces el mismo contenido, sin necesidad de consultar.
  static String deterministic(String first, String second) =>
      '${first}_$second';
}
