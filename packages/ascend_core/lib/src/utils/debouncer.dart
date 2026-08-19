import 'dart:async';

/// Agrupa llamadas seguidas en una sola.
///
/// Se usa en la validación de `@handle` mientras se escribe: sin esto haríamos
/// una lectura de Firestore por cada tecla.
class Debouncer {
  /// Crea un debouncer con la ventana de espera indicada.
  Debouncer({this.duration = const Duration(milliseconds: 350)});

  /// Tiempo de inactividad antes de ejecutar la acción.
  final Duration duration;

  Timer? _timer;

  /// Programa [action], cancelando la anterior si todavía no se ejecutó.
  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// Cancela la acción pendiente, si la hay.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// `true` si hay una acción esperando ejecutarse.
  bool get isPending => _timer?.isActive ?? false;

  /// Libera el temporizador. Llamar desde `dispose`.
  void dispose() => cancel();
}
