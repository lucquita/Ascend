import 'package:ascend_domain/ascend_domain.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Traducción de `users/{uid}/notifications/{id}` a la entidad del dominio.
///
/// Solo lectura: las notificaciones las escribe **siempre** el servidor y las
/// reglas se lo prohíben al cliente. Si la app pudiera crearlas, cualquiera
/// podría inventarse un "subiste de nivel" o, peor, un aviso de moderación
/// falso.
abstract final class NotificationDto {
  /// Convierte un documento en la notificación.
  ///
  /// Nunca lanza ante un documento incompleto: una bandeja que no abre por una
  /// fila rota es peor que una fila con el título vacío.
  static AppNotification fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();

    return AppNotification(
      id: snapshot.id,
      type: NotificationType.fromWire(_text(data['type'])),
      title: _text(data['title']) ?? 'Ascend',
      body: _text(data['body']) ?? '',
      createdAt: _date(data['createdAt']) ?? DateTime.now().toUtc(),
      // `data` viaja como mapa de texto porque es lo que admite el payload de
      // FCM: la misma forma sirve para la bandeja y para la push, y así el
      // deep link es idéntico venga de donde venga.
      data: <String, String>{
        if (data['data'] is Map)
          for (final entry in (data['data'] as Map).entries)
            if (entry.key is String && entry.value is String)
              entry.key as String: entry.value as String,
      },
      imageUrl: _text(data['imageUrl']),
      read: data['read'] == true,
      expiresAt: _date(data['expiresAt']),
    );
  }

  static String? _text(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static DateTime? _date(Object? value) => switch (value) {
    final Timestamp v => v.toDate(),
    final String v => DateTime.tryParse(v),
    _ => null,
  };
}
