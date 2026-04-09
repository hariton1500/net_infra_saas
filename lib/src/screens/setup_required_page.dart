import 'package:flutter/material.dart';

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
                  children: const [
                    Text(
                      'Supabase ещё не настроен',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Перед запуском передайте проекту два dart-define параметра: '
                      'SUPABASE_URL и SUPABASE_ANON_KEY.',
                    ),
                    SizedBox(height: 16),
                    SelectableText(
                      'flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co '
                      '--dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY',
                    ),
                    SizedBox(height: 16),
                    Text(
                      'После этого приложение покажет экран входа и onboarding компании.',
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
