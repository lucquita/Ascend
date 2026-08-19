import 'package:ascend_domain/src/enums/enums.dart';
import 'package:meta/meta.dart';

/// Categoría de objetivos (fitness, idiomas, finanzas…).
///
/// Es un catálogo global editable desde el panel: agregar una categoría no
/// requiere publicar una versión nueva de la app.
@immutable
class Category {
  /// Crea una categoría.
  const Category({
    required this.id,
    required this.names,
    required this.icon,
    required this.colorHex,
    this.descriptions = const <String, String>{},
    this.order = 0,
    this.active = true,
    this.goalsCount = 0,
  });

  /// Identificador estable (`languages`, `fitness`).
  final String id;

  /// Nombre por idioma (`{'es': 'Idiomas', 'en': 'Languages'}`).
  final Map<String, String> names;

  /// Nombre del icono.
  final String icon;

  /// Color de acento `#RRGGBB`.
  final String colorHex;

  /// Descripción por idioma.
  final Map<String, String> descriptions;

  /// Orden de presentación.
  final int order;

  /// Si se ofrece al crear objetivos.
  final bool active;

  /// Cuántos objetivos la usan (estadística del panel).
  final int goalsCount;

  /// Nombre en el idioma pedido, con reserva a español y luego a la clave.
  String nameFor(String locale) => names[locale] ?? names['es'] ?? id;

  /// Descripción en el idioma pedido.
  String? descriptionFor(String locale) =>
      descriptions[locale] ?? descriptions['es'];

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Category && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Notificación mostrada en la bandeja de la app.
@immutable
class AppNotification {
  /// Crea una notificación.
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.data = const <String, String>{},
    this.imageUrl,
    this.read = false,
    this.expiresAt,
  });

  /// Identificador.
  final String id;

  /// Tipo, que determina el icono y el destino.
  final NotificationType type;

  /// Título.
  final String title;

  /// Cuerpo.
  final String body;

  /// Momento de creación.
  final DateTime createdAt;

  /// Datos auxiliares; `data['route']` es el destino del deep link.
  final Map<String, String> data;

  /// Imagen opcional.
  final String? imageUrl;

  /// Si ya se leyó.
  final bool read;

  /// Cuándo expira. Firestore la borra sola por política TTL.
  final DateTime? expiresAt;

  /// Ruta a la que navegar al tocarla.
  String? get route => data['route'];

  /// Copia con cambios.
  AppNotification copyWith({bool? read}) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    createdAt: createdAt,
    data: data,
    imageUrl: imageUrl,
    read: read ?? this.read,
    expiresAt: expiresAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AppNotification && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Página de resultados con cursor para seguir paginando.
///
/// El cursor es opaco a propósito: el dominio no sabe que por debajo es un
/// `DocumentSnapshot` de Firestore. Si mañana cambiamos de backend, este
/// contrato no se mueve.
@immutable
class Paginated<T> {
  /// Crea una página de resultados.
  const Paginated({required this.items, this.cursor, this.hasMore = false});

  /// Página vacía.
  const Paginated.empty()
    : items = const <Never>[],
      cursor = null,
      hasMore = false;

  /// Elementos de esta página.
  final List<T> items;

  /// Cursor para pedir la siguiente página.
  final Object? cursor;

  /// Si quedan más resultados.
  final bool hasMore;

  /// `true` si no hay elementos.
  bool get isEmpty => items.isEmpty;
}
