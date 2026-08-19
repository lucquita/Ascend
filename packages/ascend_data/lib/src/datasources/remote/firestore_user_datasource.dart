import 'package:cloud_firestore/cloud_firestore.dart';

/// Acceso al documento de perfil y a la reserva de handles.
class FirestoreUserDataSource {
  /// Crea el datasource.
  const FirestoreUserDataSource(this._firestore);

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _firestore.collection('users').doc(uid);

  /// Observa el documento de perfil.
  ///
  /// `includeMetadataChanges` queda en `false`: sin eso, cada escritura emite
  /// dos veces —una desde la caché y otra al confirmar el servidor— y la
  /// pantalla parpadea.
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchUser(String uid) =>
      _userRef(uid).snapshots();

  /// Lee el perfil una vez.
  Future<DocumentSnapshot<Map<String, dynamic>>> getUser(String uid) =>
      _userRef(uid).get();

  /// Actualiza campos del perfil.
  Future<void> update(String uid, Map<String, Object?> data) =>
      _userRef(uid).update(data);

  /// Indica si un handle está libre.
  ///
  /// `handles` es de solo lectura para el cliente: alcanza para avisar mientras
  /// se escribe, pero la reserva real la hace la Function.
  Future<bool> isHandleAvailable(String handle) async {
    final snapshot = await _firestore.collection('handles').doc(handle).get();
    return !snapshot.exists;
  }

  // No existe un `touchLastLogin` a propósito. `lastLoginAt` no está entre los
  // campos que `onlyFields` autoriza al cliente en las reglas, así que
  // escribirlo desde acá haría fallar la operación entera con
  // `permission-denied`. Lo fija el servidor al crear el perfil; mantenerlo
  // fresco en cada ingreso es trabajo de un trigger, no del cliente.
}
