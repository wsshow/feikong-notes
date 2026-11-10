import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import 'pages/quill_home_page.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/l10n.dart';
import 'providers/app_lock_controller.dart';
import 'providers/app_locale_controller.dart';
import 'providers/app_theme_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/app_feedback_navigator_observer.dart';
import 'widgets/app_update_coordinator.dart';
import 'debug/debug_navigation.dart';

export 'theme/app_theme.dart';
export 'widgets/app_overlay.dart';

class FkNotesApp extends StatelessWidget {
  const FkNotesApp({super.key});

  @override
  Widget build(BuildContext context) => MediaQuery.fromView(
    view: View.of(context),
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: AppLocaleController.instance),
        ChangeNotifierProvider.value(value: AppThemeController.instance),
        ChangeNotifierProvider(
          create: (_) => AppLockController()..initialize(),
        ),
      ],
      child: Consumer2<AppLocaleController, AppThemeController>(
        builder: (context, localeController, themeController, _) => MaterialApp(
          onGenerateTitle: (context) => context.l10n.appTitle,
          locale: localeController.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            FlutterQuillLocalizations.delegate,
          ],
          debugShowCheckedModeBanner: false,
          navigatorObservers: [
            AppFeedbackNavigatorObserver(),
            if (kDebugMode) ...createDebugNavigatorObservers(),
          ],
          theme: buildAppTheme(themeController.style, Brightness.light),
          darkTheme: buildAppTheme(themeController.style, Brightness.dark),
          themeMode: themeController.effectiveMode,
          themeAnimationDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.state,
          themeAnimationCurve: Curves.easeOut,
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: appSystemOverlayStyle(Theme.of(context).brightness),
            child: AppLockGate(child: child ?? const SizedBox.shrink()),
          ),
          home: const AppUpdateCoordinator(child: QuillHomePage()),
        ),
      ),
    ),
  );
}
