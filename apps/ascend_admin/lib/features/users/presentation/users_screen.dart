import 'package:ascend_admin/features/auth/application/admin_session.dart';
import 'package:ascend_admin/shared/admin_widgets.dart';
import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Estado de la tabla de usuarios.
///
/// Guarda las páginas ya traídas, no solo la última: sin eso, "página
/// siguiente" y volver atrás implicaría releer todo desde el principio, y cada
/// relectura son 25 lecturas facturadas.
class AdminUsersState {
  /// Crea el estado.
  const AdminUsersState({
    this.users = const <AppUser>[],
    this.cursor,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.failure,
  });

  /// Personas traídas hasta ahora.
  final List<AppUser> users;

  /// Cursor de la última página.
  final Object? cursor;

  /// `true` si quedan más por traer.
  final bool hasMore;

  /// `true` mientras se trae la página siguiente.
  final bool isLoadingMore;

  /// Fallo de la última operación, si lo hubo.
  final Failure? failure;

  /// Copia cambiando lo indicado.
  AdminUsersState copyWith({
    List<AppUser>? users,
    Object? cursor,
    bool? hasMore,
    bool? isLoadingMore,
    Failure? failure,
    bool clearFailure = false,
  }) => AdminUsersState(
    users: users ?? this.users,
    cursor: cursor ?? this.cursor,
    hasMore: hasMore ?? this.hasMore,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}

/// Carga y acciones sobre la tabla de usuarios.
class AdminUsersController extends AsyncNotifier<AdminUsersState> {
  @override
  Future<AdminUsersState> build() async {
    final result = await ref.read(adminRepositoryProvider).listUsers();

    // Nunca lanza: una excepción dentro de `build()` deja el provider en
    // `AsyncLoading` para siempre y la pantalla cargando sin fin.
    return result.fold(
      onSuccess: (Paginated<AppUser> page) => AdminUsersState(
        users: page.items,
        cursor: page.cursor,
        hasMore: page.hasMore,
      ),
      onFailure: (Failure failure) => AdminUsersState(failure: failure),
    );
  }

  /// Trae la página siguiente y la suma a la lista.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.isLoadingMore) {
      return;
    }

    state = AsyncData<AdminUsersState>(
      current.copyWith(isLoadingMore: true, clearFailure: true),
    );

    final result = await ref
        .read(adminRepositoryProvider)
        .listUsers(cursor: current.cursor);

    state = AsyncData<AdminUsersState>(
      result.fold(
        onSuccess: (Paginated<AppUser> page) => current.copyWith(
          users: <AppUser>[...current.users, ...page.items],
          cursor: page.cursor,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
        onFailure: (Failure failure) =>
            current.copyWith(isLoadingMore: false, failure: failure),
      ),
    );
  }

  /// Cambia el rol de una cuenta.
  Future<bool> changeRole({
    required String targetUid,
    required UserRole role,
    String? reason,
  }) => _act(
    () => ref
        .read(setUserRoleUseCaseProvider)
        .call(
          actorUid: ref.read(adminUserProvider)?.uid ?? '',
          targetUid: targetUid,
          role: role,
          reason: reason,
        ),
  );

  /// Suspende o reactiva una cuenta.
  Future<bool> changeStatus({
    required String targetUid,
    required UserStatus status,
    String? reason,
  }) => _act(
    () => ref
        .read(setUserStatusUseCaseProvider)
        .call(
          actorUid: ref.read(adminUserProvider)?.uid ?? '',
          targetUid: targetUid,
          status: status,
          reason: reason,
        ),
  );

  /// Ejecuta una acción y recarga la tabla si salió bien.
  ///
  /// Se recarga en vez de parchear la fila en memoria porque la Cloud Function
  /// puede haber cambiado más de lo que se le pidió —revocar sesiones, tocar
  /// `updatedAt`—, y una fila optimista que no coincide con el servidor es peor
  /// que esperar medio segundo.
  Future<bool> _act(Future<Result<void>> Function() action) async {
    final current = state.value ?? const AdminUsersState();
    state = AsyncData<AdminUsersState>(current.copyWith(clearFailure: true));

    final result = await action();
    return result.fold(
      onSuccess: (_) {
        ref.invalidateSelf();
        return true;
      },
      onFailure: (Failure failure) {
        state = AsyncData<AdminUsersState>(current.copyWith(failure: failure));
        return false;
      },
    );
  }
}

/// Controlador de la tabla de usuarios.
final AsyncNotifierProvider<AdminUsersController, AdminUsersState>
adminUsersControllerProvider =
    AsyncNotifierProvider<AdminUsersController, AdminUsersState>(
      AdminUsersController.new,
      name: 'adminUsers',
    );

/// Filtro activo de la tabla.
final NotifierProvider<AdminUserFilterController, AdminUserFilter>
adminUserFilterProvider =
    NotifierProvider<AdminUserFilterController, AdminUserFilter>(
      AdminUserFilterController.new,
      name: 'adminUserFilter',
    );

/// Mantiene el filtro de la tabla.
class AdminUserFilterController extends Notifier<AdminUserFilter> {
  @override
  AdminUserFilter build() => const AdminUserFilter();

  /// Cambia el texto buscado.
  void setQuery(String query) => state = state.copyWith(query: query);

  /// Cambia el rol filtrado. `null` significa "todos".
  void setRole(UserRole? role) =>
      state = state.copyWith(role: role, clearRole: role == null);

  /// Cambia el estado filtrado. `null` significa "todos".
  void setStatus(UserStatus? status) =>
      state = state.copyWith(status: status, clearStatus: status == null);

  /// Vuelve a mostrar todo.
  void clear() => state = const AdminUserFilter();
}

/// Gestión de personas.
class UsersScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla.
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final TextEditingController _search = TextEditingController();
  final Debouncer _debouncer = Debouncer();

  @override
  void dispose() {
    _debouncer.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Copia la tabla filtrada como CSV.
  ///
  /// Se copia al portapapeles en vez de descargar un archivo: bajar un archivo
  /// desde Flutter Web exige código específico de web —y por lo tanto una
  /// dependencia o una compilación condicional— y el resultado práctico es el
  /// mismo, porque el CSV termina pegado en una hoja de cálculo. Queda anotado
  /// para la Fase 10, cuando el panel se despliegue de verdad.
  Future<void> _exportCsv(List<AppUser> users) async {
    await Clipboard.setData(ClipboardData(text: usersToCsv(users)));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${users.length} ${users.length == 1 ? 'fila copiada' : 'filas copiadas'} '
          'como CSV. Pegalo en una hoja de cálculo.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminUsersControllerProvider);
    final filter = ref.watch(adminUserFilterProvider);

    return AsyncStateBuilder<AdminUsersState>(
      value: state,
      onRetry: () => ref.invalidate(adminUsersControllerProvider),
      data: (AdminUsersState value) {
        final visible = value.users
            .where((AppUser user) => matchesAdminFilter(user, filter))
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AscendSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AdminSectionHeader(
                title: 'Usuarios',
                subtitle:
                    '${visible.length} de ${value.users.length} cargados'
                    '${value.hasMore ? ' · hay más sin traer' : ''}',
                actions: <Widget>[
                  AscendButton.secondary(
                    label: 'Exportar CSV',
                    icon: Icons.download_rounded,
                    // Dentro del `Wrap` del encabezado no hay ancho acotado:
                    // un botón a ancho completo pediría infinito y rompería
                    // el layout.
                    expanded: false,
                    onPressed: visible.isEmpty
                        ? null
                        : () => _exportCsv(visible),
                  ),
                ],
              ),
              if (value.failure != null) ...<Widget>[
                ErrorStateView(failure: value.failure!, compact: true),
                const SizedBox(height: AscendSpacing.lg),
              ],
              _Filters(controller: _search, debouncer: _debouncer),
              const SizedBox(height: AscendSpacing.lg),
              if (visible.isEmpty)
                EmptyStateView(
                  title: value.users.isEmpty
                      ? 'Todavía no hay cuentas'
                      : 'Nada coincide',
                  message: value.users.isEmpty
                      ? 'Cuando alguien se registre va a aparecer acá.'
                      : 'Probá con otro texto o quitá los filtros. La búsqueda '
                            'alcanza a las cuentas ya cargadas.',
                  icon: Icons.person_search_rounded,
                  actionLabel: filter.isEmpty ? null : 'Quitar filtros',
                  onAction: filter.isEmpty
                      ? null
                      : () {
                          _search.clear();
                          ref.read(adminUserFilterProvider.notifier).clear();
                        },
                )
              else
                AdminCard(
                  padding: EdgeInsets.zero,
                  child: AdminScrollableTable(
                    child: Column(
                      children: <Widget>[
                        for (final user in visible)
                          _UserRow(
                            user: user,
                            isSelf:
                                user.uid == ref.watch(adminUserProvider)?.uid,
                          ),
                      ],
                    ),
                  ),
                ),
              if (value.hasMore) ...<Widget>[
                const SizedBox(height: AscendSpacing.lg),
                AscendButton.secondary(
                  label: 'Cargar 25 más',
                  isLoading: value.isLoadingMore,
                  onPressed: value.isLoadingMore
                      ? null
                      : () => ref
                            .read(adminUsersControllerProvider.notifier)
                            .loadMore(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.controller, required this.debouncer});

  final TextEditingController controller;
  final Debouncer debouncer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(adminUserFilterProvider);
    final notifier = ref.read(adminUserFilterProvider.notifier);

    return Wrap(
      spacing: AscendSpacing.md,
      runSpacing: AscendSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 320,
          child: AscendTextField(
            controller: controller,
            label: 'Buscar por nombre, handle, email o uid',
            prefixIcon: Icons.search_rounded,
            // El filtrado es local, así que el debounce no ahorra red: evita
            // recomponer la tabla entera en cada tecla.
            onChanged: (String value) =>
                debouncer.run(() => notifier.setQuery(value)),
          ),
        ),
        _EnumFilter<UserRole>(
          label: 'Rol',
          values: UserRole.values,
          selected: filter.role,
          labelOf: (UserRole role) => role.wireValue,
          onSelected: notifier.setRole,
        ),
        _EnumFilter<UserStatus>(
          label: 'Estado',
          values: UserStatus.values,
          selected: filter.status,
          labelOf: (UserStatus status) => status.wireValue,
          onSelected: notifier.setStatus,
        ),
      ],
    );
  }
}

class _EnumFilter<T> extends StatelessWidget {
  const _EnumFilter({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final String label;
  final List<T> values;
  final T? selected;
  final String Function(T value) labelOf;
  final ValueChanged<T?> onSelected;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(
        '$label:',
        style: context.texts.labelMedium?.copyWith(
          color: context.ascend.textSecondary,
        ),
      ),
      const SizedBox(width: AscendSpacing.sm),
      // "Todos" es una opción explícita y no la ausencia de selección: sin
      // ella, quitar un filtro obliga a adivinar que hay que volver a tocar el
      // chip ya marcado.
      ChoiceChip(
        label: const Text('Todos'),
        selected: selected == null,
        onSelected: (_) => onSelected(null),
      ),
      for (final value in values) ...<Widget>[
        const SizedBox(width: AscendSpacing.xs),
        ChoiceChip(
          label: Text(labelOf(value)),
          selected: selected == value,
          onSelected: (_) => onSelected(value),
        ),
      ],
    ],
  );
}

class _UserRow extends ConsumerWidget {
  const _UserRow({required this.user, required this.isSelf});

  final AppUser user;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSuspended = user.status == UserStatus.suspended;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AscendSpacing.lg,
        vertical: AscendSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 18,
            child: Text(
              user.displayName.isEmpty
                  ? '?'
                  : user.displayName.characters.first.toUpperCase(),
            ),
          ),
          const SizedBox(width: AscendSpacing.md),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  user.displayName.isEmpty ? 'Sin nombre' : user.displayName,
                  style: context.texts.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  user.handle.isEmpty ? user.email : '@${user.handle}',
                  style: context.texts.bodySmall?.copyWith(
                    color: context.ascend.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: AscendSpacing.xs,
              children: <Widget>[
                if (user.role.isAdmin)
                  AdminBadge(label: 'admin', color: context.colors.primary),
                if (isSuspended)
                  AdminBadge(label: 'suspendida', color: context.colors.error),
              ],
            ),
          ),
          Expanded(
            child: Text(
              '${user.aura.total} Aura',
              style: context.texts.bodySmall?.copyWith(
                color: context.ascend.textSecondary,
              ),
            ),
          ),
          // Nadie puede tocarse a sí mismo: quitarse el rol o suspenderse deja
          // el panel sin quien lo administre. El servidor lo rechaza igual.
          if (isSelf)
            Text(
              'Vos',
              style: context.texts.labelSmall?.copyWith(
                color: context.ascend.textSecondary,
              ),
            )
          else
            _RowActions(user: user),
        ],
      ),
    );
  }
}

class _RowActions extends ConsumerWidget {
  const _RowActions({required this.user});

  final AppUser user;

  Future<void> _changeRole(BuildContext context, WidgetRef ref) async {
    final makeAdmin = !user.role.isAdmin;
    final confirmed = await _confirm(
      context,
      title: makeAdmin ? '¿Dar acceso de administrador?' : '¿Quitar el acceso?',
      message: makeAdmin
          ? '@${user.handle} va a poder ver todos los datos, moderar contenido '
                'y suspender cuentas.'
          : '@${user.handle} deja de tener acceso al panel.',
      confirmLabel: makeAdmin ? 'Dar acceso' : 'Quitar acceso',
      isDestructive: !makeAdmin,
    );
    if (!confirmed) {
      return;
    }

    await ref
        .read(adminUsersControllerProvider.notifier)
        .changeRole(
          targetUid: user.uid,
          role: makeAdmin ? UserRole.admin : UserRole.user,
        );
  }

  Future<void> _changeStatus(BuildContext context, WidgetRef ref) async {
    final suspend = user.status != UserStatus.suspended;

    // Reactivar no pide motivo: es la acción que repara. Suspender sí, y el
    // motivo se guarda en la auditoría.
    final reason = suspend
        ? await showAdminReasonDialog(
            context,
            title: '¿Por qué se suspende?',
            message:
                'La cuenta no va a poder operar y su sesión se cierra al '
                'instante.',
            confirmLabel: 'Suspender',
          )
        : null;
    if (suspend && (reason == null || reason.trim().length < 5)) {
      return;
    }

    await ref
        .read(adminUsersControllerProvider.notifier)
        .changeStatus(
          targetUid: user.uid,
          status: suspend ? UserStatus.suspended : UserStatus.active,
          reason: reason,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: 'Acciones',
    icon: const Icon(Icons.more_horiz_rounded),
    onSelected: (String value) => value == 'role'
        ? _changeRole(context, ref)
        : _changeStatus(context, ref),
    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'role',
        child: Text(
          user.role.isAdmin ? 'Quitar administrador' : 'Hacer administrador',
        ),
      ),
      PopupMenuItem<String>(
        value: 'status',
        child: Text(
          user.status == UserStatus.suspended
              ? 'Reactivar cuenta'
              : 'Suspender cuenta',
        ),
      ),
    ],
  );
}

/// Confirmación para las acciones que cuesta deshacer.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool isDestructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: isDestructive
              ? FilledButton.styleFrom(backgroundColor: context.colors.error)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
