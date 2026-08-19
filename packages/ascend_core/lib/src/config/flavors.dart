/// Entorno de ejecución.
///
/// Se elige en tiempo de compilación con `--dart-define=FLAVOR=dev|stg|prod`.
/// No se lee de un archivo ni de una variable de entorno en runtime: si el
/// entorno pudiera cambiarse después de compilar, un build de producción podría
/// terminar apuntando a la base de datos de desarrollo.
enum AppFlavor {
  /// Desarrollo local, contra el proyecto Firebase de dev y los emuladores.
  dev('dev', 'Ascend Dev'),

  /// Staging: datos realistas, usuarios de prueba.
  staging('stg', 'Ascend Staging'),

  /// Producción.
  prod('prod', 'Ascend');

  const AppFlavor(this.key, this.appName);

  /// Clave que se pasa por `--dart-define`.
  final String key;

  /// Nombre visible de la app.
  final String appName;

  /// Entorno con el que se compiló esta build.
  static final AppFlavor current = _resolve();

  static AppFlavor _resolve() {
    const value = String.fromEnvironment('FLAVOR', defaultValue: 'dev');
    return switch (value) {
      'prod' => AppFlavor.prod,
      'stg' => AppFlavor.staging,
      _ => AppFlavor.dev,
    };
  }

  /// `true` en producción.
  bool get isProd => this == AppFlavor.prod;

  /// `true` si conviene mostrar herramientas de diagnóstico en pantalla.
  bool get showsDebugTools => this != AppFlavor.prod;

  /// `true` si esta build debe apuntar a los emuladores locales.
  ///
  /// Se activa aparte del flavor porque en dev a veces querés pegarle al
  /// proyecto real de Firebase y otras veces al emulador.
  static const bool useEmulators = bool.fromEnvironment('USE_EMULATORS');
}
