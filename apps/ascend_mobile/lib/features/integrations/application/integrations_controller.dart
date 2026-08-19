import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ubicación aproximada derivada del huso horario del perfil.
///
/// No se usa el GPS a propósito: pedir permiso de ubicación para decir si va a
/// llover es desproporcionado, y la mitad de la gente lo niega. El huso ya está
/// en el perfil y da precisión de ciudad, que es la que necesita un pronóstico
/// diario.
final Provider<Coordinates?> userCoordinatesProvider = Provider<Coordinates?>((
  ref,
) {
  final profile = ref.watch(profileProvider).value?.valueOrNull;
  return coordinatesForTimezone(profile?.settings.timezone);
}, name: 'userCoordinates');

/// Pronóstico para una misión concreta.
///
/// Devuelve `null` —no un error— cuando no corresponde consultarlo o cuando la
/// API no responde. El clima es información de apoyo: bloquear una misión
/// porque no se pudo consultar el pronóstico sería absurdo.
// Sin anotación explícita: `FutureProviderFamily` no está exportado.
final missionWeatherProvider = FutureProvider.family<WeatherForecast?, Mission>(
  (ref, mission) async {
    final coords = ref.watch(userCoordinatesProvider);
    if (coords == null) {
      return null;
    }
    return ref
        .watch(checkMissionWeatherUseCaseProvider)
        .call(
          categoryId: mission.categoryId,
          dueDate: mission.dueDate,
          latitude: coords.latitude,
          longitude: coords.longitude,
        );
  },
  name: 'missionWeather',
);

/// Resultados de la búsqueda de libros.
///
/// `autoDispose` implícito por ser `family`: al cerrar el buscador, la consulta
/// se descarta en vez de quedar cacheada por un término que nadie va a repetir.
final bookSearchProvider =
    FutureProvider.family<Result<List<BookSuggestion>>, String>(
      (ref, query) => ref.watch(searchBooksUseCaseProvider).call(query),
      name: 'bookSearch',
    );
