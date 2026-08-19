import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_ui/src/organisms/ascend_skeleton.dart';
import 'package:ascend_ui/src/organisms/state_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Descripción del estado vacío de una pantalla.
@immutable
class EmptyStateConfig {
  /// Crea la configuración del estado vacío.
  const EmptyStateConfig({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_rounded,
    this.actionLabel,
    this.onAction,
  });

  /// Título.
  final String title;

  /// Mensaje con la sugerencia de qué hacer.
  final String message;

  /// Icono ilustrativo.
  final IconData icon;

  /// Etiqueta del botón principal.
  final String? actionLabel;

  /// Acción del botón principal.
  final VoidCallback? onAction;
}

/// Renderiza un [AsyncValue] cubriendo **todos** los estados posibles.
///
/// Es el único punto por el que la app pinta datos remotos. Al obligar a pasar
/// el estado vacío y ofrecer carga y error por defecto, se vuelve imposible
/// olvidarse de uno: no hay forma de escribir una pantalla que se quede en
/// blanco o que muestre una excepción cruda.
///
/// Detalle importante: si el error que llega **no** es un [Failure] —porque
/// alguien lanzó una excepción sin envolverla— se convierte igualmente en
/// [UnknownFailure]. La pantalla roja de Flutter no aparece ni en ese caso.
class AsyncStateBuilder<T> extends StatelessWidget {
  /// Crea el constructor de estados.
  const AsyncStateBuilder({
    required this.value,
    required this.data,
    this.loading,
    this.errorBuilder,
    this.emptyState,
    this.isEmpty,
    this.onRetry,
    this.skipLoadingOnRefresh = true,
    super.key,
  });

  /// El estado asincrónico a renderizar.
  final AsyncValue<T> value;

  /// Constructor del contenido cuando hay datos.
  final Widget Function(T data) data;

  /// Widget de carga. Por defecto, una lista de skeletons.
  final Widget? loading;

  /// Constructor de error personalizado. Por defecto, [ErrorStateView].
  final Widget Function(Failure failure, VoidCallback? onRetry)? errorBuilder;

  /// Configuración del estado vacío.
  final EmptyStateConfig? emptyState;

  /// Decide si los datos recibidos cuentan como "vacío".
  ///
  /// Si no se pasa, se detectan automáticamente [Iterable] y [Map] vacíos.
  final bool Function(T data)? isEmpty;

  /// Acción de reintento que se ofrece en el estado de error.
  final VoidCallback? onRetry;

  /// Si al refrescar se mantienen los datos viejos en vez de mostrar carga.
  ///
  /// Por defecto `true`: parpadear a skeleton en cada refresco es peor
  /// experiencia que ver los datos anteriores un instante más.
  final bool skipLoadingOnRefresh;

  @override
  Widget build(BuildContext context) {
    if (value.isLoading && (!skipLoadingOnRefresh || !value.hasValue)) {
      return loading ?? const AscendSkeletonList();
    }

    if (value.hasError && !value.hasValue) {
      return _buildError(value.error!, value.stackTrace);
    }

    if (value.hasValue) {
      final content = value.requireValue;
      if (_isEmptyValue(content) && emptyState != null) {
        final config = emptyState!;
        return EmptyStateView(
          title: config.title,
          message: config.message,
          icon: config.icon,
          actionLabel: config.actionLabel,
          onAction: config.onAction,
        );
      }
      return data(content);
    }

    return loading ?? const AscendSkeletonList();
  }

  Widget _buildError(Object error, StackTrace? stackTrace) {
    // Cualquier excepción suelta se normaliza a Failure: es la última línea de
    // defensa contra un error técnico llegando a la pantalla.
    final failure = error is Failure
        ? error
        : UnknownFailure(cause: error, stackTrace: stackTrace);

    return errorBuilder?.call(failure, onRetry) ??
        ErrorStateView(failure: failure, onRetry: onRetry);
  }

  bool _isEmptyValue(T content) {
    if (isEmpty != null) {
      return isEmpty!(content);
    }
    if (content is Iterable) {
      return content.isEmpty;
    }
    if (content is Map) {
      return content.isEmpty;
    }
    return false;
  }
}

/// Pantalla de reserva que reemplaza la pantalla roja de Flutter.
///
/// Se instala en `ErrorWidget.builder`, así que aparece incluso cuando un
/// widget explota durante su `build` — el único caso que [AsyncStateBuilder]
/// no puede interceptar. En release nunca se muestra el detalle técnico; en
/// debug sí, porque ahí el detalle es justamente lo que hace falta.
class AscendErrorFallback extends StatelessWidget {
  /// Crea la pantalla de reserva.
  const AscendErrorFallback({
    required this.details,
    this.showDetails = false,
    super.key,
  });

  /// Detalles del error capturado por Flutter.
  final FlutterErrorDetails details;

  /// Si se muestra el detalle técnico (solo en debug).
  final bool showDetails;

  @override
  Widget build(BuildContext context) {
    // Ojo: este widget puede construirse cuando el árbol está roto, así que no
    // asume que haya Theme, Directionality ni Material disponibles.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: const Color(0xFFF9FAFB),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Color(0x1AEF4444),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    size: 36,
                    color: Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Algo salió mal',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: const Text(
                    'Esta parte de la pantalla no pudo mostrarse. '
                    'Ya lo registramos para arreglarlo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                  ),
                ),
                if (showDetails) ...<Widget>[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      details.exceptionAsString(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
