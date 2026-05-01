import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:net_infra_saas/src/app.dart';
import 'package:net_infra_saas/src/core/app_i18n.dart';
import 'package:net_infra_saas/src/core/strings.dart';
import 'package:net_infra_saas/src/core/supabase_config.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppI18n.instance.setLocale(const Locale('en'));
  });

  testWidgets('shows setup screen when supabase is not configured', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MyApp(
        config: SupabaseConfig(url: '', anonKey: ''),
      ),
    );

    expect(find.text(AppStrings.setupSupabaseTitle), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsWidgets);
  });

  testWidgets('language menu switches visible interface text to Russian', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MyApp(
        config: SupabaseConfig(url: '', anonKey: ''),
      ),
    );

    expect(find.text(AppStrings.setupSupabaseTitle), findsOneWidget);

    await tester.tap(find.byIcon(Icons.language_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Russian').last);
    await tester.pumpAndSettle();

    expect(find.text('Supabase ещё не настроен'), findsOneWidget);
    expect(find.text(AppStrings.setupSupabaseTitle), findsNothing);
  });
}
