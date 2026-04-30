import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_translations.dart';
import 'strings.dart';

class AppI18n extends ChangeNotifier {
  AppI18n._() {
    _setDefaultLocale();
  }

  static final AppI18n instance = AppI18n._();

  static const supportedLocales = [Locale('en'), Locale('ru')];
  static const _storageKey = 'app.locale';

  Locale _locale = _resolveLocale(ui.PlatformDispatcher.instance.locale);

  Locale get locale => _locale;
  String get localeName => _locale.toLanguageTag();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedCode = prefs.getString(_storageKey);
    _locale = storedCode == null
        ? _resolveLocale(ui.PlatformDispatcher.instance.locale)
        : _resolveLocale(Locale(storedCode));
    _setDefaultLocale();
  }

  Future<void> setLocale(Locale locale) async {
    final resolved = _resolveLocale(locale);
    if (_locale == resolved) {
      return;
    }

    _locale = resolved;
    _setDefaultLocale();
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, _locale.languageCode);
  }

  String translate(String key, [Map<String, String> params = const {}]) {
    var value =
        appTranslations[_locale.languageCode]?[key] ??
        appTranslations['en']?[key] ??
        AppStrings.lookup(key);

    for (final entry in params.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value);
    }
    return value;
  }

  String formatDateTime(DateTime value) {
    return DateFormat.yMd(localeName).add_Hm().format(value);
  }

  void _setDefaultLocale() {
    Intl.defaultLocale = localeName;
  }

  static Locale _resolveLocale(Locale locale) {
    for (final supported in supportedLocales) {
      if (supported.languageCode == locale.languageCode) {
        return supported;
      }
    }
    return supportedLocales.first;
  }
}

String tr(String key, [Map<String, String> params = const {}]) {
  return AppI18n.instance.translate(key, params);
}
