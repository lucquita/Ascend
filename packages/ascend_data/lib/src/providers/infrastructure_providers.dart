/// Proveedores de infraestructura.
///
/// Son la raíz del grafo de dependencias: todo lo demás se construye a partir
/// de acá. Que estén expuestos como providers es lo que permite sustituirlos
/// por dobles en los tests con un `overrideWithValue`, sin ningún framework de
/// mocking adicional.
library;

import 'dart:async';

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/src/config/regions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' show FirebaseFunctions;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Instancia de Firebase Authentication.
final Provider<FirebaseAuth> firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
  name: 'firebaseAuth',
);

/// Instancia de Cloud Firestore.
final Provider<FirebaseFirestore> firestoreProvider =
    Provider<FirebaseFirestore>(
      (ref) => FirebaseFirestore.instance,
      name: 'firestore',
    );

/// Instancia de Firebase Storage.
final Provider<FirebaseStorage> firebaseStorageProvider =
    Provider<FirebaseStorage>(
      (ref) => FirebaseStorage.instance,
      name: 'firebaseStorage',
    );

/// Instancia de Cloud Functions.
///
/// La región se fija explícitamente: dejarla en la de por defecto añade latencia
/// desde Sudamérica y, peor, es un cambio silencioso si alguien despliega en
/// otra región.
final Provider<FirebaseFunctions> firebaseFunctionsProvider =
    Provider<FirebaseFunctions>(
      (ref) => FirebaseFunctions.instanceFor(region: kFunctionsRegion),
      name: 'firebaseFunctions',
    );

/// Instancia de Firebase Cloud Messaging.
final Provider<FirebaseMessaging> firebaseMessagingProvider =
    Provider<FirebaseMessaging>(
      (ref) => FirebaseMessaging.instance,
      name: 'firebaseMessaging',
    );

/// Instancia de Crashlytics.
final Provider<FirebaseCrashlytics> crashlyticsProvider =
    Provider<FirebaseCrashlytics>(
      (ref) => FirebaseCrashlytics.instance,
      name: 'crashlytics',
    );

/// Instancia de Analytics.
final Provider<FirebaseAnalytics> analyticsProvider =
    Provider<FirebaseAnalytics>(
      (ref) => FirebaseAnalytics.instance,
      name: 'analytics',
    );

/// Servicio de conectividad.
final Provider<Connectivity> connectivityProvider = Provider<Connectivity>(
  (ref) => Connectivity(),
  name: 'connectivity',
);

/// Emite `true` mientras haya alguna interfaz de red disponible.
///
/// Ojo con la semántica: tener wifi no garantiza que haya internet. Por eso el
/// banner offline se apoya en esto **y** en los fallos reales de las
/// operaciones, no solo en esta señal.
final StreamProvider<bool> isOnlineProvider = StreamProvider<bool>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  return connectivity.onConnectivityChanged.map(
    (results) =>
        results.isNotEmpty &&
        !results.every((r) => r == ConnectivityResult.none),
  );
}, name: 'isOnline');

/// Destino de logs que reenvía a Crashlytics.
///
/// Solo se registran advertencias y errores: mandar los `debug` gastaría cuota
/// y podría filtrar datos personales a un servicio externo.
class CrashlyticsLogSink implements LogSink {
  /// Crea el destino apuntando a una instancia de Crashlytics.
  const CrashlyticsLogSink(this._crashlytics);

  final FirebaseCrashlytics _crashlytics;

  @override
  void write(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    if (level.value < LogLevel.warning.value) {
      return;
    }

    _crashlytics.log('[${level.label}] $message');

    if (level == LogLevel.error && error != null) {
      unawaited(
        _crashlytics.recordError(
          error,
          stackTrace,
          reason: message,
          information:
              context?.entries
                  .map((e) => '${e.key}=${e.value}')
                  .toList(growable: false) ??
              const <String>[],
        ),
      );
    }
  }
}
