import 'package:ascend_core/ascend_core.dart';
import 'package:ascend_data/src/datasources/remote/firestore_category_datasource.dart';
import 'package:ascend_data/src/dtos/category_dto.dart';
import 'package:ascend_data/src/mappers/error_mapper.dart';
import 'package:ascend_domain/ascend_domain.dart';

/// Implementación de [CategoryRepository] sobre Firestore.
class CategoryRepositoryImpl implements CategoryRepository {
  /// Crea el repositorio.
  const CategoryRepositoryImpl({
    required FirestoreCategoryDataSource categoryDataSource,
  }) : _categories = categoryDataSource;

  final FirestoreCategoryDataSource _categories;

  @override
  Stream<Result<List<Category>>> watchCategories({bool onlyActive = true}) {
    return guardStream(_categories.watchCategories(onlyActive: onlyActive)).map(
      (result) => result.map(
        (snapshot) => snapshot.docs
            .map(CategoryDto.fromFirestore)
            .toList(growable: false),
      ),
    );
  }

  @override
  Future<Result<Category>> getCategory(String id) => runGuarded(() async {
    final snapshot = await _categories.getCategory(id);
    if (!snapshot.exists) {
      // Pasa cuando un objetivo viejo apunta a una categoría que se borró del
      // catálogo. La pantalla lo resuelve mostrando el id crudo, pero el
      // repositorio no puede inventar una categoría que no existe.
      throw const NotFoundFailure(code: 'category-missing');
    }
    return CategoryDto.fromFirestore(snapshot);
  });
}
