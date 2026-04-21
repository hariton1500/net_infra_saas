import 'package:flutter/material.dart';

import '../core/app_i18n.dart';
import '../widgets/language_selector.dart';

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
                    const Align(
                      alignment: Alignment.centerRight,
                      child: LanguageSelector(),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      tr('Supabase ещё не настроен'),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr(
                        'Перед запуском передайте проекту два dart-define параметра: SUPABASE_URL и SUPABASE_ANON_KEY.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const SelectableText(
                      'flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co '
                      '--dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr(
                        'После этого приложение покажет экран входа и onboarding компании.',
                      ),
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
