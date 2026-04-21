import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_controller.dart';
import 'core/app_i18n.dart';
import 'core/supabase_config.dart';
import 'screens/auth_page.dart';
import 'screens/company_setup_page.dart';
import 'screens/setup_required_page.dart';
import 'screens/start.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.config});

  final SupabaseConfig config;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AuthController? _controller;

  @override
  void initState() {
    super.initState();

    if (widget.config.isConfigured) {
      _controller = AuthController(client: Supabase.instance.client);
      _controller!.initialize();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: AppI18n.currentLocaleListenable,
      builder: (context, locale, _) {
        return MaterialApp(
          title: 'Net Infra SaaS',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(),
          locale: locale,
          supportedLocales: AppI18n.supportedLocales,
          localizationsDelegates: const [
            AppI18nDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          localeResolutionCallback: (locale, supportedLocales) {
            return AppI18n.resolve(locale);
          },
          home: widget.config.isConfigured
              ? AuthShell(controller: _controller!)
              : const SetupRequiredPage(),
        );
      },
    );
  }

  ThemeData _buildTheme() {
    const background = Color(0xFF071526);
    const surface = Color(0xFF0E223A);
    const elevated = Color(0xFF153456);
    const primary = Color(0xFF1EDDC5);
    const secondary = Color(0xFF35C886);
    const text = Color(0xFFF2F7FA);

    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: primary,
      secondary: secondary,
      surface: surface,
      error: const Color(0xFFFF6B6B),
      onPrimary: background,
      onSecondary: background,
      onSurface: text,
      onError: text,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: text,
        displayColor: text,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF224D74)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF224D74)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: Color(0xFF1D3F63)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: background,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size.fromHeight(54),
          side: const BorderSide(color: Color(0xFF2A648E)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        switch (controller.view) {
          case AuthView.loading:
            return const _LoadingScreen();
          case AuthView.signedOut:
          case AuthView.passwordRecovery:
            return AuthPage(controller: controller);
          case AuthView.needsCompanySetup:
            return CompanySetupPage(controller: controller);
          case AuthView.ready:
            return StartPage(controller: controller);
          case AuthView.error:
            return _ErrorScreen(
              message: controller.errorMessage ?? tr('Не удалось загрузить сессию.'),
              onRetry: controller.refresh,
              onSignOut: controller.signOut,
            );
        }
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  final String message;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Есть проблема с загрузкой данных'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(message),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: onRetry,
                      child: Text(tr('Повторить')),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: onSignOut,
                      child: Text(tr('Выйти из аккаунта')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
