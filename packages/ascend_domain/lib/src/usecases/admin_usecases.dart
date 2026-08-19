/// Administración: métricas, moderación, roles y auditoría.
///
/// Todo lo que el panel necesita **decidir** vive acá, en Dart puro, para poder
/// probarlo sin Firebase y sin montar un widget. El panel se limita a pintar.
library;

import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/src/entities/app_user.dart';
import 'package:ascend_domain/src/entities/category.dart';
import 'package:ascend_domain/src/entities/post.dart';
import 'package:ascend_domain/src/enums/enums.dart';
import 'package:meta/meta.dart';

/// Foto agregada del estado de la plataforma.
///
/// La calcula una función programada y se lee de un solo documento. **No se
/// arma recorriendo colecciones**: contar usuarios con un `count()` sobre toda
/// la colección cuesta una lectura por documento cada vez que alguien abre el
/// panel, y con cien mil usuarios eso es una factura por mirar un número.
@immutable
class AdminStats {
  /// Crea las métricas.
  const AdminStats({
    required this.generatedAt,
    this.usersTotal = 0,
    this.usersActive7d = 0,
    this.usersNew7d = 0,
    this.goalsActive = 0,
    this.missionsCompleted7d = 0,
    this.auraGranted7d = 0,
    this.postsTotal = 0,
    this.reportsOpen = 0,
    this.aiCallsToday = 0,
    this.aiCostUsdToday = 0,
  });

  /// Cuándo se calcularon.
  final DateTime generatedAt;

  /// Cuentas registradas.
  final int usersTotal;

  /// Cuentas con actividad en los últimos 7 días.
  final int usersActive7d;

  /// Altas de los últimos 7 días.
  final int usersNew7d;

  /// Objetivos en curso.
  final int goalsActive;

  /// Misiones completadas en los últimos 7 días.
  final int missionsCompleted7d;

  /// Aura otorgada en los últimos 7 días.
  final int auraGranted7d;

  /// Publicaciones visibles.
  final int postsTotal;

  /// Reportes sin resolver. Es el número que dispara trabajo.
  final int reportsOpen;

  /// Llamadas a la IA en el día en curso.
  final int aiCallsToday;

  /// Costo estimado de la IA en el día en curso, en dólares.
  final double aiCostUsdToday;

  /// Antigüedad de las métricas.
  Duration ageFrom(DateTime now) => now.difference(generatedAt);

  /// `true` si las métricas están tan viejas que conviene desconfiar.
  ///
  /// El umbral son 48 horas: la agregación corre a diario, así que dos días sin
  /// actualizarse significa que falló y nadie se enteró. Mostrar números viejos
  /// como si fueran de hoy es peor que no mostrar nada.
  bool isStaleAt(DateTime now) => ageFrom(now) > const Duration(hours: 48);
}

/// Entrada del registro de auditoría.
///
/// Es inmutable incluso para los administradores —las reglas prohíben escribir
/// esta colección desde cualquier cliente—: un registro que quien audita puede
/// borrar no sirve para auditar.
@immutable
class AuditEntry {
  /// Crea la entrada.
  const AuditEntry({
    required this.id,
    required this.action,
    required this.actorUid,
    required this.createdAt,
    this.targetUid,
    this.targetId,
    this.details = const <String, Object?>{},
  });

  /// Identificador.
  final String id;

  /// Qué se hizo (`set_user_role`, `resolve_report`…).
  final String action;

  /// Quién lo hizo.
  final String actorUid;

  /// Sobre qué cuenta.
  final String? targetUid;

  /// Sobre qué documento.
  final String? targetId;

  /// Datos extra de la acción.
  final Map<String, Object?> details;

  /// Cuándo.
  final DateTime createdAt;

  /// Texto legible de la acción.
  String get actionLabel => switch (action) {
    'set_user_role' => 'Cambio de rol',
    'set_user_status' => 'Cambio de estado de cuenta',
    'resolve_report' => 'Resolución de reporte',
    'update_category' => 'Cambio en el catálogo',
    _ => action,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AuditEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Decisión que toma quien modera sobre un reporte.
enum ModerationAction {
  /// El contenido se oculta del feed.
  hideContent('hide_content'),

  /// El reporte no procede.
  dismiss('dismiss'),

  /// El contenido se oculta y la cuenta queda suspendida.
  suspendAuthor('suspend_author');

  const ModerationAction(this.wireValue);

  /// Valor que viaja a la Cloud Function.
  final String wireValue;

  /// Texto del botón.
  String get label => switch (this) {
    ModerationAction.hideContent => 'Ocultar contenido',
    ModerationAction.dismiss => 'Descartar reporte',
    ModerationAction.suspendAuthor => 'Ocultar y suspender',
  };

  /// `true` si la acción es difícil de revertir y conviene confirmarla.
  bool get needsConfirmation => this == ModerationAction.suspendAuthor;
}

/// Filtro de la tabla de usuarios.
@immutable
class AdminUserFilter {
  /// Crea el filtro.
  const AdminUserFilter({this.query = '', this.role, this.status});

  /// Texto libre: nombre, handle o email.
  final String query;

  /// Rol exacto.
  final UserRole? role;

  /// Estado exacto.
  final UserStatus? status;

  /// `true` si no filtra nada.
  bool get isEmpty => query.trim().isEmpty && role == null && status == null;

  /// Copia cambiando lo indicado.
  ///
  /// `clearRole`/`clearStatus` existen porque con `role ?? this.role` no hay
  /// forma de volver a "todos": pasar `null` significaría "no lo cambies".
  AdminUserFilter copyWith({
    String? query,
    UserRole? role,
    UserStatus? status,
    bool clearRole = false,
    bool clearStatus = false,
  }) => AdminUserFilter(
    query: query ?? this.query,
    role: clearRole ? null : (role ?? this.role),
    status: clearStatus ? null : (status ?? this.status),
  );
}

/// `true` si la persona pasa el filtro.
///
/// El filtrado de texto es local a propósito: Firestore no sabe buscar
/// subcadenas —solo prefijos exactos sobre un campo indexado—, así que la
/// alternativa real sería sumar un motor de búsqueda entero. Para el volumen de
/// un panel que pagina de a 25, filtrar la página en memoria alcanza y no suma
/// infraestructura. Queda anotado como límite conocido: la búsqueda alcanza a
/// lo que ya se trajo, no a toda la colección.
bool matchesAdminFilter(AppUser user, AdminUserFilter filter) {
  if (filter.role != null && user.role != filter.role) {
    return false;
  }
  if (filter.status != null && user.status != filter.status) {
    return false;
  }

  final query = filter.query.trim().toLowerCase();
  if (query.isEmpty) {
    return true;
  }
  return user.displayName.toLowerCase().contains(query) ||
      user.handle.toLowerCase().contains(query) ||
      user.email.toLowerCase().contains(query) ||
      user.uid.toLowerCase() == query;
}

/// Prioridad de un reporte en la bandeja de moderación.
///
/// Una bandeja ordenada solo por fecha hace que lo grave espere detrás de lo
/// trivial. Este orden pone primero lo que puede hacer daño real.
int reportPriority(Report report) => switch (report.reason) {
  ReportReason.violence => 0,
  ReportReason.harassment => 1,
  ReportReason.nsfw => 2,
  ReportReason.fakeAchievement => 3,
  ReportReason.spam => 4,
  ReportReason.other => 5,
};

/// Ordena la bandeja: primero lo grave, y a igual gravedad, lo más viejo.
///
/// Lo más viejo primero y no lo más nuevo: un reporte que lleva días esperando
/// es alguien a quien ya le fallamos. Con el orden inverso, los reportes de una
/// racha activa empujan a los viejos hacia abajo para siempre.
List<Report> sortModerationQueue(List<Report> reports) {
  final sorted = <Report>[...reports]
    ..sort((Report a, Report b) {
      final byPriority = reportPriority(a).compareTo(reportPriority(b));
      return byPriority != 0 ? byPriority : a.createdAt.compareTo(b.createdAt);
    });
  return sorted;
}

/// Repositorio de administración.
///
/// Todas las escrituras pasan por Cloud Functions y no por Firestore directo,
/// aunque las reglas se lo permitirían al admin. El motivo es el registro de
/// auditoría: `auditLog` es inescribible desde cualquier cliente, así que la
/// única forma de garantizar que **toda** acción administrativa quede asentada
/// es que la acción y su registro ocurran en la misma transacción del servidor.
abstract interface class AdminRepository {
  /// Observa las métricas agregadas.
  Stream<Result<AdminStats>> watchStats();

  /// Página de usuarios, ordenada por fecha de alta descendente.
  Future<Result<Paginated<AppUser>>> listUsers({
    Object? cursor,
    int limit = 25,
  });

  /// Observa la cola de moderación pendiente.
  Stream<Result<List<Report>>> watchOpenReports({int limit = 50});

  /// Observa el registro de auditoría, del más reciente al más viejo.
  Stream<Result<List<AuditEntry>>> watchAuditLog({int limit = 100});

  /// Cambia el rol de una cuenta. Ejecuta `setUserRole`.
  Future<Result<void>> setUserRole({
    required String targetUid,
    required UserRole role,
    String? reason,
  });

  /// Suspende o reactiva una cuenta. Ejecuta `setUserStatus`.
  Future<Result<void>> setUserStatus({
    required String targetUid,
    required UserStatus status,
    String? reason,
  });

  /// Resuelve un reporte aplicando una acción. Ejecuta `moderateContent`.
  Future<Result<void>> resolveReport({
    required String reportId,
    required ModerationAction action,
    String? note,
  });

  /// Da de alta o modifica una categoría del catálogo.
  Future<Result<void>> saveCategory(Category category);
}

/// Cambia el rol de una cuenta, con las salvaguardas del panel.
class SetUserRoleUseCase {
  /// Crea el caso de uso.
  const SetUserRoleUseCase(this._admin);

  final AdminRepository _admin;

  /// Aplica el cambio.
  ///
  /// Rechaza en el cliente el caso de cambiarse el rol a uno mismo. El servidor
  /// lo rechaza igual —es la autoridad—, pero avisarlo acá evita una llamada de
  /// red para recibir un error que ya se sabía.
  Future<Result<void>> call({
    required String actorUid,
    required String targetUid,
    required UserRole role,
    String? reason,
  }) async {
    if (actorUid == targetUid) {
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.admin.selfRoleChange',
          field: 'targetUid',
        ),
      );
    }
    return _admin.setUserRole(targetUid: targetUid, role: role, reason: reason);
  }
}

/// Suspende o reactiva una cuenta.
class SetUserStatusUseCase {
  /// Crea el caso de uso.
  const SetUserStatusUseCase(this._admin);

  final AdminRepository _admin;

  /// Aplica el cambio.
  ///
  /// Suspenderse a uno mismo deja el panel sin quien lo administre, igual que
  /// quitarse el rol: se rechaza por el mismo motivo.
  Future<Result<void>> call({
    required String actorUid,
    required String targetUid,
    required UserStatus status,
    String? reason,
  }) async {
    if (actorUid == targetUid) {
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.admin.selfStatusChange',
          field: 'targetUid',
        ),
      );
    }
    if (status == UserStatus.suspended &&
        (reason == null || reason.trim().length < 5)) {
      // Una suspensión sin motivo es una decisión que nadie puede revisar
      // después, ni siquiera quien la tomó.
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.admin.reasonRequired',
          field: 'reason',
        ),
      );
    }
    return _admin.setUserStatus(
      targetUid: targetUid,
      status: status,
      reason: reason,
    );
  }
}

/// Resuelve un reporte de la bandeja de moderación.
class ResolveReportUseCase {
  /// Crea el caso de uso.
  const ResolveReportUseCase(this._admin);

  final AdminRepository _admin;

  /// Aplica la decisión.
  Future<Result<void>> call({
    required String reportId,
    required ModerationAction action,
    String? note,
  }) async {
    if (reportId.trim().isEmpty) {
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.admin.reportRequired',
          field: 'reportId',
        ),
      );
    }
    if (action == ModerationAction.suspendAuthor &&
        (note == null || note.trim().length < 5)) {
      return const Failed<void>(
        ValidationFailure(
          messageKey: 'validation.admin.reasonRequired',
          field: 'note',
        ),
      );
    }
    return _admin.resolveReport(reportId: reportId, action: action, note: note);
  }
}

/// Exporta usuarios a CSV.
///
/// Es una función pura y no un método del repositorio porque exportar no toca
/// la red: transforma lo que ya está en pantalla. Así se prueba entera, que es
/// donde importa —una exportación mal escapada corrompe el archivo entero—.
String usersToCsv(List<AppUser> users) => toCsv(
  headers: const <String>[
    'uid',
    'handle',
    'nombre',
    'email',
    'rol',
    'estado',
    'aura',
    'racha',
    'alta',
  ],
  rows: <List<Object?>>[
    for (final user in users)
      <Object?>[
        user.uid,
        user.handle,
        user.displayName,
        user.email,
        user.role.wireValue,
        user.status.wireValue,
        user.aura.total,
        user.stats.currentStreak,
        user.createdAt,
      ],
  ],
);

/// Exporta el registro de auditoría a CSV.
String auditToCsv(List<AuditEntry> entries) => toCsv(
  headers: const <String>[
    'id',
    'accion',
    'actor',
    'objetivo',
    'fecha',
    'detalle',
  ],
  rows: <List<Object?>>[
    for (final entry in entries)
      <Object?>[
        entry.id,
        entry.action,
        entry.actorUid,
        entry.targetUid ?? entry.targetId,
        entry.createdAt,
        entry.details.isEmpty ? '' : entry.details.toString(),
      ],
  ],
);
