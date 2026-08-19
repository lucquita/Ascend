import 'package:ascend_admin/router/admin_router.dart';
import 'package:ascend_ui/ascend_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Raíz del panel de administración.
class AscendAdminApp extends ConsumerWidget {
  /// Crea el panel.
  const AscendAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => AscendFailureMessages(
    resolve: AscendFailureMessages.defaultResolver,
    child: MaterialApp.router(
      title: 'Ascend · Panel',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(adminRouterProvider),
      theme: AscendTheme.light,
      darkTheme: AscendTheme.dark,
    ),
  );
}
