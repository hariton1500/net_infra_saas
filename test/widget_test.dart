import 'package:flutter_test/flutter_test.dart';

import 'package:net_infra_saas/src/app.dart';
import 'package:net_infra_saas/src/core/strings.dart';
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

    expect(find.text(AppStrings.setupSupabaseTitle), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsWidgets);
  });
}
