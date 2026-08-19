/// Capa de datos de Ascend.
///
/// Es la única capa que conoce Firebase. Implementa los contratos declarados en
/// `ascend_domain` y garantiza que ninguna excepción de infraestructura llegue
/// más arriba: todo sale como `Result<T, Failure>`.
library;

export 'src/config/app_check_service.dart';
export 'src/config/firebase_config.dart';
export 'src/config/regions.dart';
export 'src/datasources/local/evidence_outbox.dart';
export 'src/datasources/remote/ascend_http_client.dart';
export 'src/datasources/remote/firebase_auth_datasource.dart';
export 'src/datasources/remote/firebase_messaging_datasource.dart';
export 'src/datasources/remote/firestore_aura_datasource.dart';
export 'src/datasources/remote/firestore_category_datasource.dart';
export 'src/datasources/remote/firestore_community_datasource.dart';
export 'src/datasources/remote/firestore_goal_datasource.dart';
export 'src/datasources/remote/firestore_mission_datasource.dart';
export 'src/datasources/remote/firestore_user_datasource.dart';
export 'src/dtos/admin_dto.dart';
export 'src/dtos/aura_dto.dart';
export 'src/dtos/category_dto.dart';
export 'src/dtos/goal_dto.dart';
export 'src/dtos/mission_dto.dart';
export 'src/dtos/notification_dto.dart';
export 'src/dtos/post_dto.dart';
export 'src/dtos/user_dto.dart';
export 'src/mappers/error_mapper.dart';
export 'src/providers/infrastructure_providers.dart';
export 'src/providers/repository_providers.dart';
export 'src/repositories/admin_repository_impl.dart';
export 'src/repositories/ai_repository_impl.dart';
export 'src/repositories/aura_repository_impl.dart';
export 'src/repositories/auth_repository_impl.dart';
export 'src/repositories/category_repository_impl.dart';
export 'src/repositories/community_repository_impl.dart';
export 'src/repositories/evidence_repository_impl.dart';
export 'src/repositories/goal_repository_impl.dart';
export 'src/repositories/integration_repository_impl.dart';
export 'src/repositories/mission_repository_impl.dart';
export 'src/repositories/notification_repository_impl.dart';
export 'src/repositories/user_repository_impl.dart';
