// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:net_infra_saas/src/app.dart';
import 'package:net_infra_saas/src/core/supabase_config.dart';

void main() {
  testWidgets('shows setup screen when supabase is not configured', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MyApp(
        config: SupabaseConfig(url: '', anonKey: ''),
      ),
    );

    expect(find.text('Supabase ещё не настроен'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsWidgets);
  });
}
