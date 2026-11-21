import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/di/service_locator.dart';
import 'core/theme/app_theme.dart';
import 'data/services/local_settings_service.dart';
import 'data/services/session_service.dart';
import 'routes/routes.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final GoRouter _router = createRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionService>.value(
          value: getIt<SessionService>(),
        ),
        ChangeNotifierProvider<LocalSettingsService>.value(
          value: getIt<LocalSettingsService>(),
        ),
      ],
      child: Consumer<LocalSettingsService>(
        builder: (context, localSettings, _) => MaterialApp.router(
          title: 'BuildPro',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.forSettings(localSettings),
          builder: (context, child) {
            final scale = localSettings.displayComfort.textScale;
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(scale)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          routerConfig: _router,
        ),
      ),
    );
  }
}
