import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_domain/ascend_domain.dart';
import 'package:ascend_mobile/features/integrations/application/integrations_controller.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Abre el buscador de libros y devuelve el elegido, o `null` si se cerró.
///
/// Es una hoja modal y no una pantalla: buscar un libro es un paso dentro de
/// crear la misión, no un destino propio. Si fuera una ruta, volver atrás con
/// el gesto del sistema perdería lo ya escrito en el formulario.
Future<BookSuggestion?> showBookPicker(BuildContext context) =>
    showModalBottomSheet<BookSuggestion>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext sheetContext) => const _BookPickerSheet(),
    );

class _BookPickerSheet extends ConsumerStatefulWidget {
  const _BookPickerSheet();

  @override
  ConsumerState<_BookPickerSheet> createState() => _BookPickerSheetState();
}

class _BookPickerSheetState extends ConsumerState<_BookPickerSheet> {
  final TextEditingController _query = TextEditingController();

  /// Sin el debounce se dispararía una llamada por cada tecla contra un
  /// catálogo gratuito que nos deja consultarlo por buena voluntad.
  final Debouncer _debouncer = Debouncer();

  /// Término efectivamente buscado, que va por detrás de lo que se está
  /// tecleando. Vacío significa "todavía no se buscó nada".
  String _submitted = '';

  @override
  void dispose() {
    _debouncer.dispose();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debouncer.run(() {
      if (!mounted) {
        return;
      }
      setState(() => _submitted = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    // La hoja se acota a media pantalla y sube con el teclado: sin esto, el
    // teclado taparía justamente los resultados que hay que elegir.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        expand: false,
        builder: (BuildContext context, ScrollController scrollController) =>
            Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AscendSpacing.lg,
                    AscendSpacing.lg,
                    AscendSpacing.lg,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Buscar un libro', style: context.texts.titleLarge),
                      const SizedBox(height: AscendSpacing.sm),
                      Text(
                        'Los datos salen de Open Library, un catálogo abierto.',
                        style: context.texts.bodySmall?.copyWith(
                          color: context.ascend.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AscendSpacing.lg),
                      AscendTextField(
                        controller: _query,
                        label: 'Título o autor',
                        hint: 'El nombre del viento',
                        prefixIcon: Icons.search_rounded,
                        textInputAction: TextInputAction.search,
                        autofocus: true,
                        onChanged: _onChanged,
                        onSubmitted: (String value) =>
                            setState(() => _submitted = value.trim()),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _Results(
                    query: _submitted,
                    scrollController: scrollController,
                  ),
                ),
              ],
            ),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.scrollController});

  final String query;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Por debajo de tres caracteres ni se consulta: el caso de uso lo
    // rechazaría igual, y mostrar ese rechazo como error sería absurdo cuando
    // la persona simplemente todavía no terminó de escribir.
    if (query.length < 3) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AscendSpacing.lg),
          child: EmptyStateView(
            title: 'Escribí un título',
            message: 'Con tres letras alcanza para empezar a buscar.',
            icon: Icons.menu_book_outlined,
          ),
        ),
      );
    }

    final search = ref.watch(bookSearchProvider(query));

    return AsyncStateBuilder<Result<List<BookSuggestion>>>(
      value: search,
      onRetry: () => ref.invalidate(bookSearchProvider(query)),
      data: (Result<List<BookSuggestion>> result) => result.fold<Widget>(
        onFailure: (Failure failure) => Padding(
          padding: const EdgeInsets.all(AscendSpacing.lg),
          child: ErrorStateView(
            failure: failure,
            onRetry: () => ref.invalidate(bookSearchProvider(query)),
          ),
        ),
        onSuccess: (List<BookSuggestion> books) {
          if (books.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(AscendSpacing.lg),
              child: EmptyStateView(
                title: 'Sin resultados',
                message: 'Probá con otro título, o escribí la misión a mano.',
                icon: Icons.search_off_rounded,
              ),
            );
          }

          return ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(vertical: AscendSpacing.sm),
            itemCount: books.length,
            itemBuilder: (BuildContext context, int index) =>
                _BookTile(book: books[index]),
          );
        },
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book});

  final BookSuggestion book;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (book.author != null) book.author!,
      if (book.firstPublishYear != null) '${book.firstPublishYear}',
      if (book.pageCount != null) '${book.pageCount} págs.',
    ];

    return ListTile(
      // La portada es decorativa: si no carga, la fila sigue siendo usable.
      leading: book.coverUrl == null
          ? const Icon(Icons.menu_book_outlined)
          : Image.network(
              book.coverUrl!,
              width: 40,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(Icons.menu_book_outlined),
            ),
      title: Text(book.title),
      subtitle: parts.isEmpty ? null : Text(parts.join(' · ')),
      onTap: () => Navigator.of(context).pop(book),
    );
  }
}
