import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/core/app_i18n.dart';
import 'src/core/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppI18n.instance.load();

  final config = SupabaseConfig.fromEnvironment();

  if (config.isConfigured) {
    await config.initialize();
  }

  runApp(MyApp(config: config));
}
