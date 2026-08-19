/// Serialización a CSV, para exportar las tablas del panel.
///
/// Se escribe a mano en lugar de sumar una dependencia porque el formato son
/// cuatro reglas (RFC 4180) y la parte difícil no es generarlo sino **escapar
/// bien**, que es justamente lo que cualquier implementación casera hace mal.
/// Acá está resuelto y probado.
library;

/// Convierte filas en un CSV.
///
/// [headers] es la primera fila. Cada fila de [rows] debe tener la misma
/// cantidad de columnas; las que falten se completan vacías en vez de correr
/// las columnas siguientes, que es el error que arruina una exportación entera
/// sin que se note hasta abrirla.
///
/// El separador de línea es `\r\n` porque lo pide el RFC y porque es lo único
/// que Excel abre bien en Windows sin preguntar nada.
String toCsv({
  required List<String> headers,
  required List<List<Object?>> rows,
  String separator = ',',
}) {
  final buffer = StringBuffer()
    ..write(headers.map((h) => _escape(h, separator)).join(separator))
    ..write('\r\n');

  for (final row in rows) {
    final cells = <String>[
      for (var i = 0; i < headers.length; i++)
        _escape(i < row.length ? _stringify(row[i]) : '', separator),
    ];
    buffer
      ..write(cells.join(separator))
      ..write('\r\n');
  }

  return buffer.toString();
}

String _stringify(Object? value) => switch (value) {
  null => '',
  // Las fechas van en ISO 8601 UTC: es el único formato que una hoja de
  // cálculo interpreta igual en cualquier configuración regional.
  final DateTime date => date.toUtc().toIso8601String(),
  final bool flag => flag ? 'true' : 'false',
  _ => value.toString(),
};

/// Escapa una celda según el RFC 4180.
///
/// Va entre comillas si contiene el separador, comillas o un salto de línea, y
/// las comillas internas se duplican. Sin esto, un nombre con una coma parte la
/// fila en dos columnas y desplaza todo lo que sigue.
///
/// El apóstrofo delante de `=`, `+`, `-` y `@` no es cosmético: sin él, una
/// celda que empieza con `=` la ejecuta Excel como fórmula. Es una inyección
/// real (*CSV injection*), y en una exportación de datos de usuarios el
/// contenido de la celda lo escribió alguien de afuera.
String _escape(String value, String separator) {
  var cell = value;

  if (cell.isNotEmpty && <String>{'=', '+', '-', '@'}.contains(cell[0])) {
    cell = "'$cell";
  }

  final needsQuotes =
      cell.contains(separator) ||
      cell.contains('"') ||
      cell.contains('\n') ||
      cell.contains('\r');

  return needsQuotes ? '"${cell.replaceAll('"', '""')}"' : cell;
}
