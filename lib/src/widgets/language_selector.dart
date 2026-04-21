import 'package:flutter/material.dart';

import '../core/app_i18n.dart';

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final activeLocale = AppI18n.of(context).locale;

    return PopupMenuButton<Locale>(
      tooltip: tr('Язык'),
      initialValue: AppI18n.resolve(activeLocale),
      onSelected: AppI18n.updateCurrent,
      itemBuilder: (context) => [
        for (final locale in AppI18n.supportedLocales)
          PopupMenuItem<Locale>(
            value: locale,
            child: Text(AppI18n.localeLabel(locale)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0C1D33),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFF1E466A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, size: 18),
            const SizedBox(width: 8),
            Text(
              AppI18n.localeLabel(activeLocale),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
