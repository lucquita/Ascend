import 'package:ascend_admin/shared/admin_widgets.dart';
import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/ascend_data.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Todas las categorías, activas e inactivas.
///
/// El panel usa un provider propio en vez de `categoriesProvider`: aquel filtra
/// a las activas, que es lo correcto para la app pero deja fuera justamente lo
/// que hay que poder reactivar desde acá.
final StreamProvider<Result<List<Category>>> allCategoriesProvider =
    StreamProvider<Result<List<Category>>>(
      (ref) => ref
          .watch(categoryRepositoryProvider)
          .watchCategories(onlyActive: false),
      name: 'allCategories',
    );

/// Alta y edición del catálogo.
class CategoryFormController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Guarda una categoría.
  Future<bool> save(Category category) async {
    state = const AsyncLoading<void>();
    final result = await guardResult(
      () => ref.read(adminRepositoryProvider).saveCategory(category),
    );

    return result.fold(
      onSuccess: (_) {
        state = const AsyncData<void>(null);
        return true;
      },
      onFailure: (Failure failure) {
        state = AsyncError<void>(
          failure,
          failure.stackTrace ?? StackTrace.empty,
        );
        return false;
      },
    );
  }
}

/// Controlador del catálogo.
final NotifierProvider<CategoryFormController, AsyncValue<void>>
categoryFormControllerProvider =
    NotifierProvider<CategoryFormController, AsyncValue<void>>(
      CategoryFormController.new,
      name: 'categoryForm',
    );

/// Catálogo de categorías.
///
/// Es la sección que desbloquea todo lo demás: sin categorías cargadas nadie
/// puede crear un objetivo, así que la semilla inicial se carga desde acá y no
/// con un script que haya que correr a mano.
class CategoriesScreen extends ConsumerWidget {
  /// Crea la pantalla.
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(allCategoriesProvider);
    final form = ref.watch(categoryFormControllerProvider);
    final failure = form.error is Failure ? form.error! as Failure : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AscendSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AdminSectionHeader(
            title: 'Categorías',
            subtitle: 'Sin categorías cargadas no se puede crear un objetivo.',
            actions: <Widget>[
              AscendButton(
                label: 'Nueva categoría',
                icon: Icons.add_rounded,
                expanded: false,
                onPressed: form.isLoading
                    ? null
                    : () => _openForm(context, ref, null),
              ),
            ],
          ),
          if (failure != null) ...<Widget>[
            ErrorStateView(failure: failure, compact: true),
            const SizedBox(height: AscendSpacing.lg),
          ],
          AsyncStateBuilder<Result<List<Category>>>(
            value: categories,
            onRetry: () => ref.invalidate(allCategoriesProvider),
            data: (Result<List<Category>> result) => result.fold<Widget>(
              onFailure: (Failure f) => ErrorStateView(
                failure: f,
                onRetry: () => ref.invalidate(allCategoriesProvider),
              ),
              onSuccess: (List<Category> items) => items.isEmpty
                  ? EmptyStateView(
                      title: 'El catálogo está vacío',
                      message:
                          'Cargá las categorías iniciales para que la app '
                          'permita crear objetivos.',
                      icon: Icons.category_outlined,
                      actionLabel: 'Cargar catálogo inicial',
                      onAction: () => _seed(context, ref),
                    )
                  : Column(
                      children: <Widget>[
                        for (final category in items)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AscendSpacing.sm,
                            ),
                            child: _CategoryRow(
                              category: category,
                              onEdit: () => _openForm(context, ref, category),
                              onToggle: () => ref
                                  .read(categoryFormControllerProvider.notifier)
                                  .save(_toggled(category)),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Carga la semilla documentada en el modelo de datos.
  ///
  /// Existe porque el catálogo inicial estaba pendiente de un script manual, y
  /// un paso manual que nadie corre es una app que no se puede usar.
  Future<void> _seed(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(categoryFormControllerProvider.notifier);
    var saved = 0;

    for (final seed in kSeedCategories) {
      if (await controller.save(seed)) {
        saved++;
      }
    }

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$saved de ${kSeedCategories.length} categorías creadas.',
        ),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    Category? existing,
  ) async {
    final category = await showDialog<Category>(
      context: context,
      builder: (BuildContext context) => _CategoryDialog(existing: existing),
    );
    if (category != null) {
      await ref.read(categoryFormControllerProvider.notifier).save(category);
    }
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.onEdit,
    required this.onToggle,
  });

  final Category category;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => AdminCard(
    padding: const EdgeInsets.symmetric(
      horizontal: AscendSpacing.lg,
      vertical: AscendSpacing.md,
    ),
    child: Row(
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _colorOf(category.colorHex, context),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AscendSpacing.md),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                category.names['es'] ?? category.id,
                style: context.texts.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                category.id,
                style: context.texts.bodySmall?.copyWith(
                  color: context.ascend.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Text(
            '${category.goalsCount} objetivos',
            style: context.texts.bodySmall?.copyWith(
              color: context.ascend.textSecondary,
            ),
          ),
        ),
        if (!category.active)
          AdminBadge(label: 'inactiva', color: context.ascend.textSecondary),
        const SizedBox(width: AscendSpacing.md),
        IconButton(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Editar',
        ),
        // No hay borrado: una categoría con objetivos apuntando a ella dejaría
        // esos objetivos huérfanos. Desactivarla la saca de la app y conserva
        // lo ya creado.
        IconButton(
          onPressed: onToggle,
          icon: Icon(
            category.active
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
          tooltip: category.active ? 'Desactivar' : 'Reactivar',
        ),
      ],
    ),
  );

  static Color _colorOf(String hex, BuildContext context) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return value == null ? context.colors.primary : Color(0xFF000000 | value);
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.existing});

  final Category? existing;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _id = TextEditingController(
    text: widget.existing?.id ?? '',
  );
  late final TextEditingController _nameEs = TextEditingController(
    text: widget.existing?.names['es'] ?? '',
  );
  late final TextEditingController _nameEn = TextEditingController(
    text: widget.existing?.names['en'] ?? '',
  );
  late final TextEditingController _color = TextEditingController(
    text: widget.existing?.colorHex ?? '#3B82F6',
  );
  late final TextEditingController _icon = TextEditingController(
    text: widget.existing?.icon ?? 'category',
  );

  String? _idError;

  @override
  void dispose() {
    _id.dispose();
    _nameEs.dispose();
    _nameEn.dispose();
    _color.dispose();
    _icon.dispose();
    super.dispose();
  }

  void _submit() {
    final id = _id.text.trim().toLowerCase();
    // El id es la clave del documento y queda desnormalizado en cada objetivo y
    // cada misión: cambiarlo después rompería esas referencias, así que se
    // valida acá y no se permite editarlo.
    final invalid =
        id.isEmpty || !RegExp(r'^[a-z][a-z0-9_]{2,29}$').hasMatch(id);
    if (invalid) {
      setState(
        () => _idError =
            'Minúsculas, números y guion bajo. Entre 3 y 30 caracteres.',
      );
      return;
    }
    if (_nameEs.text.trim().isEmpty) {
      return;
    }

    Navigator.of(context).pop(
      Category(
        id: id,
        names: <String, String>{
          'es': _nameEs.text.trim(),
          if (_nameEn.text.trim().isNotEmpty) 'en': _nameEn.text.trim(),
        },
        icon: _icon.text.trim().isEmpty ? 'category' : _icon.text.trim(),
        colorHex: _color.text.trim(),
        descriptions: widget.existing?.descriptions ?? const <String, String>{},
        order: widget.existing?.order ?? 0,
        active: widget.existing?.active ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing == null ? 'Nueva categoría' : 'Editar categoría',
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AscendTextField(
              controller: _id,
              label: 'Identificador',
              hint: 'languages',
              errorText: _idError,
              // Editar el id sería crear otra categoría y dejar huérfanos los
              // objetivos que apuntaban a la anterior.
              enabled: widget.existing == null,
              autofocus: widget.existing == null,
              onChanged: (_) {
                if (_idError != null) {
                  setState(() => _idError = null);
                }
              },
            ),
            AscendTextField(
              controller: _nameEs,
              label: 'Nombre en español',
              hint: 'Idiomas',
            ),
            AscendTextField(
              controller: _nameEn,
              label: 'Nombre en inglés (opcional)',
              hint: 'Languages',
            ),
            AscendTextField(
              controller: _icon,
              label: 'Icono',
              hint: 'translate',
            ),
            AscendTextField(
              controller: _color,
              label: 'Color',
              hint: '#3B82F6',
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Guardar')),
    ],
  );
}

/// Copia de una categoría con el estado invertido.
///
/// `Category` no tiene `copyWith`, y agregárselo solo para esto obligaría a
/// resolver el problema de los campos que se limpian con `null` —el mismo que
/// ya apareció en `Goal` y en `Milestone`— para un único uso.
Category _toggled(Category category) => Category(
  id: category.id,
  names: category.names,
  icon: category.icon,
  colorHex: category.colorHex,
  descriptions: category.descriptions,
  order: category.order,
  active: !category.active,
  goalsCount: category.goalsCount,
);

/// Catálogo inicial documentado en `01-MODELO-DATOS.md`.
///
/// Vive en el panel y no en un script: un paso manual que nadie corre es una
/// app que no se puede usar, y cargarlo desde acá deja la operación registrada
/// como cualquier otra escritura del catálogo.
const List<Category> kSeedCategories = <Category>[
  Category(
    id: 'fitness',
    names: <String, String>{'es': 'Fitness', 'en': 'Fitness'},
    icon: 'fitness_center',
    colorHex: '#EF4444',
    order: 1,
  ),
  Category(
    id: 'languages',
    names: <String, String>{'es': 'Idiomas', 'en': 'Languages'},
    icon: 'translate',
    colorHex: '#3B82F6',
    order: 2,
  ),
  Category(
    id: 'business',
    names: <String, String>{'es': 'Negocios', 'en': 'Business'},
    icon: 'business_center',
    colorHex: '#0EA5E9',
    order: 3,
  ),
  Category(
    id: 'reading',
    names: <String, String>{'es': 'Lectura', 'en': 'Reading'},
    icon: 'menu_book',
    colorHex: '#8B5CF6',
    order: 4,
  ),
  Category(
    id: 'finance',
    names: <String, String>{'es': 'Finanzas', 'en': 'Finance'},
    icon: 'savings',
    colorHex: '#22C55E',
    order: 5,
  ),
  Category(
    id: 'travel',
    names: <String, String>{'es': 'Viajes', 'en': 'Travel'},
    icon: 'flight_takeoff',
    colorHex: '#F59E0B',
    order: 6,
  ),
  Category(
    id: 'mindfulness',
    names: <String, String>{'es': 'Bienestar', 'en': 'Mindfulness'},
    icon: 'self_improvement',
    colorHex: '#14B8A6',
    order: 7,
  ),
  Category(
    id: 'skills',
    names: <String, String>{'es': 'Habilidades', 'en': 'Skills'},
    icon: 'construction',
    colorHex: '#6366F1',
    order: 8,
  ),
  Category(
    id: 'creativity',
    names: <String, String>{'es': 'Creatividad', 'en': 'Creativity'},
    icon: 'palette',
    colorHex: '#EC4899',
    order: 9,
  ),
  Category(
    id: 'relationships',
    names: <String, String>{'es': 'Vínculos', 'en': 'Relationships'},
    icon: 'diversity_3',
    colorHex: '#F97316',
    order: 10,
  ),
];
