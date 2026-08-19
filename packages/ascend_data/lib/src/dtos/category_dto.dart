import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Traducción entre `categories/{categoryId}` y [Category].
///
/// El catálogo es de **solo lectura para el cliente** (`allow write: if isAdmin()`),
/// así que este DTO no tiene métodos de escritura: los alta y baja se hacen
/// desde el panel en la Fase 8. Agregar acá un `toCreate` sería ofrecer una
/// operación que las reglas van a rechazar siempre.
abstract final class CategoryDto {
  /// Convierte un documento de Firestore en la entidad.
  static Category fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => fromMap(snapshot.data() ?? const <String, dynamic>{}, id: snapshot.id);

  /// Convierte un mapa plano en la entidad.
  static Category fromMap(Map<String, dynamic> data, {required String id}) =>
      Category(
        id: id,
        names: _localizedOf(data['name']),
        icon: _stringOf(data['icon'], fallback: 'category'),
        // Si falta el color, se usa el primario de la marca en vez de dejar la
        // tarjeta sin acento.
        colorHex: _stringOf(data['colorHex'], fallback: '#3B82F6'),
        descriptions: _localizedOf(data['description']),
        order: _intOf(data['order']),
        // `active` ausente se interpreta como activa: una categoría del
        // catálogo sin el campo es un documento viejo, no una categoría dada
        // de baja.
        active: data['active'] != false,
        goalsCount: _intOf(data['goalsCount']),
      );

  /// Lee un mapa `{es: '…', en: '…'}` descartando valores que no sean texto.
  static Map<String, String> _localizedOf(Object? value) {
    if (value is! Map) {
      return const <String, String>{};
    }
    final result = <String, String>{};
    value.forEach((key, dynamic entry) {
      if (key is String && entry is String && entry.isNotEmpty) {
        result[key] = entry;
      }
    });
    return Map<String, String>.unmodifiable(result);
  }

  static String _stringOf(Object? value, {String fallback = ''}) =>
      value is String && value.isNotEmpty ? value : fallback;

  static int _intOf(Object? value, {int fallback = 0}) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    _ => fallback,
  };
}

/// Escrituras del catálogo, reservadas al panel de administración.
///
/// Va aparte de [CategoryDto] para que quede explícito que **el cliente móvil
/// nunca escribe categorías**: las reglas solo se lo permiten a un admin, y
/// tener el mapa de escritura en la misma clase que la lectura invitaba a
/// llamarlo desde cualquier lado.
abstract final class CategoryWriteDto {
  /// Documento completo de una categoría.
  ///
  /// No incluye `goalsCount`: ese contador lo mantiene el servidor y
  /// sobrescribirlo desde el panel pondría el catálogo en cero cada vez que
  /// alguien edita un nombre.
  static Map<String, Object?> toWrite(Category category) => <String, Object?>{
    'name': category.names,
    'description': category.descriptions,
    'icon': category.icon,
    'colorHex': category.colorHex,
    'order': category.order,
    'active': category.active,
  };
}
