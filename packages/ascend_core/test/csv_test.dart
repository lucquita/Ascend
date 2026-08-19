import 'package:ascend_core/ascend_core.dart';
import 'package:test/test.dart';

/// La parte difícil de un CSV no es generarlo sino escaparlo. Un escape mal
/// hecho no falla: produce un archivo que abre igual y tiene los datos
/// corridos de columna, y nadie se entera hasta que alguien toma una decisión
/// con esos números.
void main() {
  group('toCsv', () {
    test('escribe encabezados y filas', () {
      final csv = toCsv(
        headers: <String>['a', 'b'],
        rows: <List<Object?>>[
          <Object?>[1, 2],
        ],
      );

      expect(csv, 'a,b\r\n1,2\r\n');
    });

    test('termina las líneas con CRLF', () {
      // Lo pide el RFC 4180 y es lo único que Excel en Windows abre sin
      // preguntar nada.
      final csv = toCsv(headers: <String>['a'], rows: <List<Object?>>[]);
      expect(csv, 'a\r\n');
    });

    test('entrecomilla una celda con el separador adentro', () {
      // Sin esto, un nombre con coma parte la fila en dos columnas y desplaza
      // todo lo que sigue.
      final csv = toCsv(
        headers: <String>['nombre'],
        rows: <List<Object?>>[
          <Object?>['Pérez, Ana'],
        ],
      );

      expect(csv, 'nombre\r\n"Pérez, Ana"\r\n');
    });

    test('duplica las comillas internas', () {
      final csv = toCsv(
        headers: <String>['t'],
        rows: <List<Object?>>[
          <Object?>['dijo "hola"'],
        ],
      );

      expect(csv, 't\r\n"dijo ""hola"""\r\n');
    });

    test('entrecomilla los saltos de línea', () {
      final csv = toCsv(
        headers: <String>['t'],
        rows: <List<Object?>>[
          <Object?>['dos\nlíneas'],
        ],
      );

      expect(csv, 't\r\n"dos\nlíneas"\r\n');
    });

    test('neutraliza una fórmula de hoja de cálculo', () {
      // Inyección de CSV: una celda que empieza con `=` la ejecuta Excel al
      // abrir el archivo, y en una exportación de usuarios ese texto lo
      // escribió alguien de afuera.
      final csv = toCsv(
        headers: <String>['nombre'],
        rows: <List<Object?>>[
          <Object?>['=1+1'],
          <Object?>['@SUM(A1)'],
          <Object?>['+cmd'],
          <Object?>['-2'],
        ],
      );

      expect(csv, contains("'=1+1"));
      expect(csv, contains("'@SUM(A1)"));
      expect(csv, contains("'+cmd"));
      expect(csv, contains("'-2"));
    });

    test('una fila corta se completa vacía, no corre las columnas', () {
      // Es el error que arruina la exportación entera sin que se note hasta
      // abrirla: los datos aparecen bajo el encabezado equivocado.
      final csv = toCsv(
        headers: <String>['a', 'b', 'c'],
        rows: <List<Object?>>[
          <Object?>[1],
        ],
      );

      expect(csv, 'a,b,c\r\n1,,\r\n');
    });

    test('las fechas van en ISO 8601 UTC', () {
      // Es el único formato que una hoja de cálculo interpreta igual en
      // cualquier configuración regional.
      final csv = toCsv(
        headers: <String>['f'],
        rows: <List<Object?>>[
          <Object?>[DateTime.utc(2026, 8, 17, 12, 30)],
        ],
      );

      expect(csv, contains('2026-08-17T12:30:00.000Z'));
    });

    test('un null queda vacío, no como la palabra null', () {
      final csv = toCsv(
        headers: <String>['a', 'b'],
        rows: <List<Object?>>[
          <Object?>[null, true],
        ],
      );

      expect(csv, 'a,b\r\n,true\r\n');
    });

    test('respeta un separador distinto', () {
      final csv = toCsv(
        headers: <String>['a', 'b'],
        rows: <List<Object?>>[
          <Object?>['x;y', 'z'],
        ],
        separator: ';',
      );

      expect(csv, 'a;b\r\n"x;y";z\r\n');
    });
  });
}
