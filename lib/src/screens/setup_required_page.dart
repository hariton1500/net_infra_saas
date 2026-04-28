import 'package:flutter/material.dart';

import '../core/app_i18n.dart';
import '../core/strings.dart';
import '../widgets/screen_instruction.dart';

class SetupRequiredPage extends StatelessWidget {
  const SetupRequiredPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
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
                      tr(AppStrings.setupSupabaseTitle),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(tr(AppStrings.setupSupabaseBody)),
                    const SizedBox(height: 16),
                    ScreenInstruction(
                      text: tr(
                        'Add both dart-define values, restart the app, and continue from the sign-in screen.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const SelectableText(
                      'flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co '
                      '--dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY',
                    ),
                    const SizedBox(height: 16),
                    Text(tr(AppStrings.setupSupabaseAfter)),
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
