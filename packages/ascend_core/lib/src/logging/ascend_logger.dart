import 'dart:developer' as developer;

/// Severidad de un registro.
enum LogLevel {
  /// Detalle fino, solo útil depurando.
  debug(500, 'DEBUG'),

  /// Hito normal del flujo.
  info(800, 'INFO'),

  /// Algo raro que no impide continuar.
  warning(900, 'WARN'),

  /// Falló algo que debería haber funcionado.
  error(1000, 'ERROR');

  const LogLevel(this.value, this.label);

  /// Valor numérico que entiende `dart:developer`.
  final int value;

  /// Etiqueta corta para la consola.
  final String label;
}

/// Destino al que se envían los registros.
///
/// La capa de datos implementa uno que escribe en Crashlytics; los tests usan
/// uno en memoria. `ascend_core` no depende de Firebase, así que solo define
/// el contrato.
abstract interface class LogSink {
  /// Recibe un registro ya formateado.
  void write(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  });
}

/// Logger de Ascend.
///
/// En este proyecto no se usa `print`: el lint lo prohíbe. Todo pasa por acá,
/// lo que permite decidir en un único lugar qué se manda a Crashlytics y qué
/// se descarta en release.
class AscendLogger {
  /// Crea un logger con un [name] que identifica el subsistema.
  const AscendLogger(this.name);

  /// Nombre del subsistema (por ejemplo `GoalRepository`).
  final String name;

  static final List<LogSink> _sinks = <LogSink>[];
  static LogLevel _minimumLevel = LogLevel.debug;

  /// Registra un destino adicional (Crashlytics, archivo, tests).
  static void addSink(LogSink sink) => _sinks.add(sink);

  /// Elimina todos los destinos. Útil entre tests.
  static void clearSinks() => _sinks.clear();

  /// Define el nivel mínimo que se registra. En release se sube a
  /// [LogLevel.warning] para no filtrar información ni gastar batería.
  static set minimumLevel(LogLevel level) => _minimumLevel = level;

  /// Registro de depuración.
  void debug(String message, {Map<String, Object?>? context}) =>
      _log(LogLevel.debug, message, context: context);

  /// Registro informativo.
  void info(String message, {Map<String, Object?>? context}) =>
      _log(LogLevel.info, message, context: context);

  /// Advertencia recuperable.
  void warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) => _log(
    LogLevel.warning,
    message,
    error: error,
    stackTrace: stackTrace,
    context: context,
  );

  /// Error: siempre se propaga a todos los destinos.
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) => _log(
    LogLevel.error,
    message,
    error: error,
    stackTrace: stackTrace,
    context: context,
  );

  void _log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?>? context,
  }) {
    if (level.value < _minimumLevel.value) {
      return;
    }

    developer.log(
      message,
      name: name,
      level: level.value,
      error: error,
      stackTrace: stackTrace,
    );

    for (final sink in _sinks) {
      sink.write(
        level,
        message,
        error: error,
        stackTrace: stackTrace,
        context: <String, Object?>{'logger': name, ...?context},
      );
    }
  }
}
