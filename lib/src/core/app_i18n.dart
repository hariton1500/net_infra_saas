import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppI18n {
  AppI18n(this.locale);

  final Locale locale;

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('es'),
    Locale('ru'),
    Locale('zh'),
    Locale('hi'),
    Locale('ar'),
  ];

  static const Map<String, String> supportedLocaleLabels = {
    'en': 'English',
    'es': 'Espa\u00f1ol',
    'ru': '\u0420\u0443\u0441\u0441\u043a\u0438\u0439',
    'zh': '\u4e2d\u6587',
    'hi': '\u0939\u093f\u0928\u094d\u0926\u0940',
    'ar': '\u0627\u0644\u0639\u0631\u0628\u064a\u0629',
  };

  static final ValueNotifier<Locale> _currentLocale = ValueNotifier<Locale>(
    supportedLocales.first,
  );

  static AppI18n current = AppI18n(supportedLocales.first);

  static AppI18n of(BuildContext context) {
    return Localizations.of<AppI18n>(context, AppI18n) ?? current;
  }

  static Locale resolve(Locale? locale) {
    if (locale == null) {
      return supportedLocales.first;
    }
    for (final supported in supportedLocales) {
      if (supported.languageCode == locale.languageCode) {
        return supported;
      }
    }
    return supportedLocales.first;
  }

  static void updateCurrent(Locale locale) {
    final resolved = resolve(locale);
    _currentLocale.value = resolved;
    current = AppI18n(resolved);
  }

  static ValueListenable<Locale> get currentLocaleListenable => _currentLocale;

  static String localeLabel(Locale locale) {
    final resolved = resolve(locale);
    return supportedLocaleLabels[resolved.languageCode] ?? resolved.languageCode;
  }

  String tr(String key, [Map<String, String> params = const {}]) {
    final lang = resolve(locale).languageCode;
    final translated = lang == 'ru'
        ? key
        : _translations[lang]?[key] ?? _translations['en']?[key] ?? key;
    if (params.isEmpty) {
      return translated;
    }

    var value = translated;
    for (final entry in params.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value);
    }
    return value;
  }
}

class AppI18nDelegate extends LocalizationsDelegate<AppI18n> {
  const AppI18nDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppI18n.supportedLocales.any(
      (supported) => supported.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppI18n> load(Locale locale) {
    final resolved = AppI18n.resolve(locale);
    AppI18n.updateCurrent(resolved);
    return SynchronousFuture<AppI18n>(AppI18n.current);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppI18n> old) => false;
}

extension AppI18nBuildContext on BuildContext {
  AppI18n get l10n => AppI18n.of(this);
}

String tr(String key, [Map<String, String> params = const {}]) =>
    AppI18n.current.tr(key, params);

const _kLanguage = '\u042f\u0437\u044b\u043a';
const _kUser = '\u041f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044c';
const _kCompany = '\u041a\u043e\u043c\u043f\u0430\u043d\u0438\u044f';
const _kProfile = '\u041f\u0440\u043e\u0444\u0438\u043b\u044c';
const _kRefreshData = '\u041e\u0431\u043d\u043e\u0432\u0438\u0442\u044c \u0434\u0430\u043d\u043d\u044b\u0435';
const _kWorkAreas = '\u0420\u0430\u0431\u043e\u0447\u0438\u0435 \u0440\u0430\u0437\u0434\u0435\u043b\u044b';
const _kOwner = '\u0412\u043b\u0430\u0434\u0435\u043b\u0435\u0446';
const _kAdministrator = '\u0410\u0434\u043c\u0438\u043d\u0438\u0441\u0442\u0440\u0430\u0442\u043e\u0440';
const _kEmployee = '\u0421\u043e\u0442\u0440\u0443\u0434\u043d\u0438\u043a';
const _kSignInTab = '\u0412\u0445\u043e\u0434';
const _kSignUpTab = '\u0420\u0435\u0433\u0438\u0441\u0442\u0440\u0430\u0446\u0438\u044f';
const _kEmployeeSignIn = '\u0412\u0445\u043e\u0434 \u0434\u043b\u044f \u0441\u043e\u0442\u0440\u0443\u0434\u043d\u0438\u043a\u043e\u0432';
const _kUseWorkEmail =
    '\u0418\u0441\u043f\u043e\u043b\u044c\u0437\u0443\u0439\u0442\u0435 \u0440\u0430\u0431\u043e\u0447\u0438\u0439 email \u0438 \u043f\u0430\u0440\u043e\u043b\u044c, \u0447\u0442\u043e\u0431\u044b \u043e\u0442\u043a\u0440\u044b\u0442\u044c \u043f\u0440\u043e\u0441\u0442\u0440\u0430\u043d\u0441\u0442\u0432\u043e \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u0438.';
const _kWorkEmail = '\u0420\u0430\u0431\u043e\u0447\u0438\u0439 email';
const _kPassword = '\u041f\u0430\u0440\u043e\u043b\u044c';
const _kResetPassword = '\u0412\u043e\u0441\u0441\u0442\u0430\u043d\u043e\u0432\u0438\u0442\u044c \u043f\u0430\u0440\u043e\u043b\u044c';
const _kSignIn = '\u0412\u043e\u0439\u0442\u0438';
const _kOwnerRegistration =
    '\u0420\u0435\u0433\u0438\u0441\u0442\u0440\u0430\u0446\u0438\u044f \u0432\u043b\u0430\u0434\u0435\u043b\u044c\u0446\u0430 \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u0438';
const _kCreateFirstCompanyAccount =
    '\u0421\u043e\u0437\u0434\u0430\u0439\u0442\u0435 \u043f\u0435\u0440\u0432\u044b\u0439 \u0430\u043a\u043a\u0430\u0443\u043d\u0442 \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u0438. \u041f\u043e\u0441\u043b\u0435 \u044d\u0442\u043e\u0433\u043e \u043c\u043e\u0436\u043d\u043e \u0431\u0443\u0434\u0435\u0442 \u0434\u043e\u0431\u0430\u0432\u043b\u044f\u0442\u044c \u0441\u043e\u0442\u0440\u0443\u0434\u043d\u0438\u043a\u043e\u0432.';
const _kYourName = '\u0412\u0430\u0448\u0435 \u0438\u043c\u044f';
const _kPosition = '\u0414\u043e\u043b\u0436\u043d\u043e\u0441\u0442\u044c';
const _kCompanyName = '\u041d\u0430\u0437\u0432\u0430\u043d\u0438\u0435 \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u0438';
const _kGoToSignIn = '\u041f\u0435\u0440\u0435\u0439\u0442\u0438 \u043a\u043e \u0432\u0445\u043e\u0434\u0443';
const _kCreateCompany = '\u0421\u043e\u0437\u0434\u0430\u0442\u044c \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u044e';
const _kRequiredField = '\u041f\u043e\u043b\u0435 \u043e\u0431\u044f\u0437\u0430\u0442\u0435\u043b\u044c\u043d\u043e.';
const _kEnterEmail = '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 email.';
const _kEnterValidEmail = '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u043a\u043e\u0440\u0440\u0435\u043a\u0442\u043d\u044b\u0439 email.';
const _kEnterPassword = '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u043f\u0430\u0440\u043e\u043b\u044c.';
const _kMin8 = '\u041c\u0438\u043d\u0438\u043c\u0443\u043c 8 \u0441\u0438\u043c\u0432\u043e\u043b\u043e\u0432.';
const _kAccountAlreadyExistsTry =
    '\u0410\u043a\u043a\u0430\u0443\u043d\u0442 \u0441 \u0442\u0430\u043a\u0438\u043c email \u0443\u0436\u0435 \u0441\u0443\u0449\u0435\u0441\u0442\u0432\u0443\u0435\u0442. \u041f\u043e\u043f\u0440\u043e\u0431\u0443\u0439\u0442\u0435 \u0432\u043e\u0439\u0442\u0438 \u0438\u043b\u0438 \u0432\u043e\u0441\u0441\u0442\u0430\u043d\u043e\u0432\u0438\u0442\u044c \u043f\u0430\u0440\u043e\u043b\u044c.';
const _kAccountAlreadyExistsGo =
    '\u0410\u043a\u043a\u0430\u0443\u043d\u0442 \u0441 \u0442\u0430\u043a\u0438\u043c email \u0443\u0436\u0435 \u0441\u0443\u0449\u0435\u0441\u0442\u0432\u0443\u0435\u0442. \u041f\u0435\u0440\u0435\u0439\u0434\u0438\u0442\u0435 \u043a\u043e \u0432\u0445\u043e\u0434\u0443 \u0438\u043b\u0438 \u0432\u043e\u0441\u0441\u0442\u0430\u043d\u043e\u0432\u0438\u0442\u0435 \u043f\u0430\u0440\u043e\u043b\u044c.';
const _kFailedSignIn = '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0432\u043e\u0439\u0442\u0438.';
const _kFailedCreateAccount = '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0441\u043e\u0437\u0434\u0430\u0442\u044c \u0430\u043a\u043a\u0430\u0443\u043d\u0442.';
const _kEnterWorkEmailForReset =
    '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u0440\u0430\u0431\u043e\u0447\u0438\u0439 email. \u041c\u044b \u043e\u0442\u043f\u0440\u0430\u0432\u0438\u043c \u043f\u0438\u0441\u044c\u043c\u043e \u0441\u043e \u0441\u0441\u044b\u043b\u043a\u043e\u0439 \u0434\u043b\u044f \u0441\u043c\u0435\u043d\u044b \u043f\u0430\u0440\u043e\u043b\u044f.';
const _kSendEmail = '\u041e\u0442\u043f\u0440\u0430\u0432\u0438\u0442\u044c \u043f\u0438\u0441\u044c\u043c\u043e';
const _kCancel = '\u041e\u0442\u043c\u0435\u043d\u0430';
const _kRecoveryEmailSent =
    '\u041c\u044b \u043e\u0442\u043f\u0440\u0430\u0432\u0438\u043b\u0438 \u043f\u0438\u0441\u044c\u043c\u043e \u0434\u043b\u044f \u0432\u043e\u0441\u0441\u0442\u0430\u043d\u043e\u0432\u043b\u0435\u043d\u0438\u044f \u043f\u0430\u0440\u043e\u043b\u044f, \u0435\u0441\u043b\u0438 \u0430\u043a\u043a\u0430\u0443\u043d\u0442 \u0441 \u0442\u0430\u043a\u0438\u043c email \u0441\u0443\u0449\u0435\u0441\u0442\u0432\u0443\u0435\u0442.';
const _kEnterEmailForRecovery =
    '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 email \u0434\u043b\u044f \u0432\u043e\u0441\u0441\u0442\u0430\u043d\u043e\u0432\u043b\u0435\u043d\u0438\u044f \u043f\u0430\u0440\u043e\u043b\u044f.';
const _kFailedSendRecoveryEmail =
    '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043e\u0442\u043f\u0440\u0430\u0432\u0438\u0442\u044c \u043f\u0438\u0441\u044c\u043c\u043e \u0434\u043b\u044f \u0432\u043e\u0441\u0441\u0442\u0430\u043d\u043e\u0432\u043b\u0435\u043d\u0438\u044f \u043f\u0430\u0440\u043e\u043b\u044f.';
const _kSetNewPassword = '\u0417\u0430\u0434\u0430\u0439\u0442\u0435 \u043d\u043e\u0432\u044b\u0439 \u043f\u0430\u0440\u043e\u043b\u044c';
const _kRecoveryConfirmed =
    '\u041c\u044b \u043f\u043e\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u043b\u0438 \u0441\u0441\u044b\u043b\u043a\u0443 \u0432\u043e\u0441\u0441\u0442\u0430\u043d\u043e\u0432\u043b\u0435\u043d\u0438\u044f. \u0422\u0435\u043f\u0435\u0440\u044c \u043c\u043e\u0436\u043d\u043e \u0437\u0430\u0434\u0430\u0442\u044c \u043d\u043e\u0432\u044b\u0439 \u043f\u0430\u0440\u043e\u043b\u044c \u0434\u043b\u044f \u0430\u043a\u043a\u0430\u0443\u043d\u0442\u0430.';
const _kNewPassword = '\u041d\u043e\u0432\u044b\u0439 \u043f\u0430\u0440\u043e\u043b\u044c';
const _kRepeatNewPassword = '\u041f\u043e\u0432\u0442\u043e\u0440\u0438\u0442\u0435 \u043d\u043e\u0432\u044b\u0439 \u043f\u0430\u0440\u043e\u043b\u044c';
const _kPasswordsMismatch = '\u041f\u0430\u0440\u043e\u043b\u0438 \u043d\u0435 \u0441\u043e\u0432\u043f\u0430\u0434\u0430\u044e\u0442.';
const _kSaveNewPassword = '\u0421\u043e\u0445\u0440\u0430\u043d\u0438\u0442\u044c \u043d\u043e\u0432\u044b\u0439 \u043f\u0430\u0440\u043e\u043b\u044c';
const _kExitRecoveryMode = '\u0412\u044b\u0439\u0442\u0438 \u0438\u0437 \u0440\u0435\u0436\u0438\u043c\u0430 \u0432\u043e\u0441\u0441\u0442\u0430\u043d\u043e\u0432\u043b\u0435\u043d\u0438\u044f';
const _kFailedUpdatePassword = '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043e\u0431\u043d\u043e\u0432\u0438\u0442\u044c \u043f\u0430\u0440\u043e\u043b\u044c.';
const _kPasswordUpdated = '\u041f\u0430\u0440\u043e\u043b\u044c \u043e\u0431\u043d\u043e\u0432\u043b\u0451\u043d.';
const _kEnterNewPassword = '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u043d\u043e\u0432\u044b\u0439 \u043f\u0430\u0440\u043e\u043b\u044c.';
const _kInfraManagement =
    '\u0423\u043f\u0440\u0430\u0432\u043b\u0435\u043d\u0438\u0435 \u0438\u043d\u0444\u0440\u0430\u0441\u0442\u0440\u0443\u043a\u0442\u0443\u0440\u043e\u0439 \u0434\u043b\u044f \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u0439 \u0438 \u0438\u0445 \u043a\u043e\u043c\u0430\u043d\u0434';
const _kPlatformDescription =
    '\u0412\u0445\u043e\u0434\u0438\u0442\u0435 \u0432 \u0440\u0430\u0431\u043e\u0447\u0435\u0435 \u043f\u0440\u043e\u0441\u0442\u0440\u0430\u043d\u0441\u0442\u0432\u043e \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u0438, \u0441\u043e\u0437\u0434\u0430\u0432\u0430\u0439\u0442\u0435 \u043f\u0435\u0440\u0432\u0443\u044e \u043e\u0440\u0433\u0430\u043d\u0438\u0437\u0430\u0446\u0438\u044e \u0438 \u0433\u043e\u0442\u043e\u0432\u044c\u0442\u0435 \u0434\u043e\u0441\u0442\u0443\u043f \u0434\u043b\u044f \u0441\u043e\u0442\u0440\u0443\u0434\u043d\u0438\u043a\u043e\u0432 \u043d\u0430 \u043e\u0431\u0449\u0435\u0439 \u043f\u043b\u0430\u0442\u0444\u043e\u0440\u043c\u0435.';
const _kOneAccountPerCompany = '\u041e\u0434\u0438\u043d \u0430\u043a\u043a\u0430\u0443\u043d\u0442 \u043d\u0430 \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u044e';
const _kOwnerCreatesWorkspace =
    '\u0412\u043b\u0430\u0434\u0435\u043b\u0435\u0446 \u0441\u043e\u0437\u0434\u0430\u0451\u0442 \u0440\u0430\u0431\u043e\u0447\u0435\u0435 \u043f\u0440\u043e\u0441\u0442\u0440\u0430\u043d\u0441\u0442\u0432\u043e \u0438 \u0437\u0430\u0442\u0435\u043c \u0434\u043e\u0431\u0430\u0432\u043b\u044f\u0435\u0442 \u0441\u043e\u0442\u0440\u0443\u0434\u043d\u0438\u043a\u043e\u0432.';
const _kSupabaseSessions = '\u0421\u0435\u0441\u0441\u0438\u0438 Supabase';
const _kAppRestoresSession =
    '\u041f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u0435 \u0430\u0432\u0442\u043e\u043c\u0430\u0442\u0438\u0447\u0435\u0441\u043a\u0438 \u0432\u043e\u0441\u0441\u0442\u0430\u043d\u0430\u0432\u043b\u0438\u0432\u0430\u0435\u0442 \u0430\u043a\u0442\u0438\u0432\u043d\u0443\u044e \u0441\u0435\u0441\u0441\u0438\u044e \u043f\u043e\u043b\u044c\u0437\u043e\u0432\u0430\u0442\u0435\u043b\u044f.';
const _kReadyForMultiTenant = '\u0413\u043e\u0442\u043e\u0432\u043e \u0434\u043b\u044f multi-tenant';
const _kProfilesSeparated =
    '\u041f\u0440\u043e\u0444\u0438\u043b\u0438, \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u0438 \u0438 \u0440\u043e\u043b\u0438 \u0441\u043e\u0442\u0440\u0443\u0434\u043d\u0438\u043a\u043e\u0432 \u0443\u0436\u0435 \u0440\u0430\u0437\u0434\u0435\u043b\u0435\u043d\u044b \u043d\u0430 \u0443\u0440\u043e\u0432\u043d\u0435 \u0431\u0430\u0437\u044b.';
const _kSupabaseNotConfigured = 'Supabase \u0435\u0449\u0451 \u043d\u0435 \u043d\u0430\u0441\u0442\u0440\u043e\u0435\u043d';
const _kSupabaseDefineHelp =
    '\u041f\u0435\u0440\u0435\u0434 \u0437\u0430\u043f\u0443\u0441\u043a\u043e\u043c \u043f\u0435\u0440\u0435\u0434\u0430\u0439\u0442\u0435 \u043f\u0440\u043e\u0435\u043a\u0442\u0443 \u0434\u0432\u0430 dart-define \u043f\u0430\u0440\u0430\u043c\u0435\u0442\u0440\u0430: SUPABASE_URL \u0438 SUPABASE_ANON_KEY.';
const _kAppShowsSignIn =
    '\u041f\u043e\u0441\u043b\u0435 \u044d\u0442\u043e\u0433\u043e \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u0435 \u043f\u043e\u043a\u0430\u0436\u0435\u0442 \u044d\u043a\u0440\u0430\u043d \u0432\u0445\u043e\u0434\u0430 \u0438 onboarding \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u0438.';
const _kCompleteCompanySetup = '\u0417\u0430\u0432\u0435\u0440\u0448\u0438\u0442\u0435 \u043d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0443 \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u0438';
const _kSignedInAsButNoWorkspace =
    '\u0412\u044b \u0432\u043e\u0448\u043b\u0438 \u043a\u0430\u043a {email}, \u043d\u043e \u0440\u0430\u0431\u043e\u0447\u0435\u0435 \u043f\u0440\u043e\u0441\u0442\u0440\u0430\u043d\u0441\u0442\u0432\u043e \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u0438 \u0435\u0449\u0451 \u043d\u0435 \u0441\u043e\u0437\u0434\u0430\u043d\u043e.';
const _kEnterCompanyName = '\u0423\u043a\u0430\u0436\u0438\u0442\u0435 \u043d\u0430\u0437\u0432\u0430\u043d\u0438\u0435 \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u0438.';
const _kCreateWorkspace = '\u0421\u043e\u0437\u0434\u0430\u0442\u044c \u0440\u0430\u0431\u043e\u0447\u0435\u0435 \u043f\u0440\u043e\u0441\u0442\u0440\u0430\u043d\u0441\u0442\u0432\u043e';
const _kFailedCompleteCompanySetup =
    '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0437\u0430\u0432\u0435\u0440\u0448\u0438\u0442\u044c \u043d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0443 \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u0438.';
const _kCompanyConnected =
    '\u041a\u043e\u043c\u043f\u0430\u043d\u0438\u044f \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0430, \u0443\u0447\u0451\u0442\u043d\u0430\u044f \u0437\u0430\u043f\u0438\u0441\u044c \u0433\u043e\u0442\u043e\u0432\u0430.';
const _kEmployeeProfile = '\u041f\u0440\u043e\u0444\u0438\u043b\u044c \u0441\u043e\u0442\u0440\u0443\u0434\u043d\u0438\u043a\u0430';
const _kPersonalData = '\u041b\u0438\u0447\u043d\u044b\u0435 \u0434\u0430\u043d\u043d\u044b\u0435';
const _kProfileDescription =
    '\u0417\u0434\u0435\u0441\u044c \u043c\u043e\u0436\u043d\u043e \u043e\u0431\u043d\u043e\u0432\u0438\u0442\u044c \u0438\u043c\u044f \u0438 \u0434\u043e\u043b\u0436\u043d\u043e\u0441\u0442\u044c. Email \u0438 \u0440\u043e\u043b\u044c \u0434\u043e\u0441\u0442\u0443\u043f\u043d\u044b \u0442\u043e\u043b\u044c\u043a\u043e \u0434\u043b\u044f \u043f\u0440\u043e\u0441\u043c\u043e\u0442\u0440\u0430.';
const _kRoleInCompany = '\u0420\u043e\u043b\u044c \u0432 \u043a\u043e\u043c\u043f\u0430\u043d\u0438\u0438';
const _kEmployeeName = '\u0418\u043c\u044f \u0441\u043e\u0442\u0440\u0443\u0434\u043d\u0438\u043a\u0430';
const _kEnterEmployeeName = '\u0412\u0432\u0435\u0434\u0438\u0442\u0435 \u0438\u043c\u044f \u0441\u043e\u0442\u0440\u0443\u0434\u043d\u0438\u043a\u0430.';
const _kSaveProfile = '\u0421\u043e\u0445\u0440\u0430\u043d\u0438\u0442\u044c \u043f\u0440\u043e\u0444\u0438\u043b\u044c';
const _kProfileUpdated = '\u041f\u0440\u043e\u0444\u0438\u043b\u044c \u043e\u0431\u043d\u043e\u0432\u043b\u0451\u043d.';
const _kFailedUpdateProfile = '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043e\u0431\u043d\u043e\u0432\u0438\u0442\u044c \u043f\u0440\u043e\u0444\u0438\u043b\u044c.';
const _kProblemLoadingData = '\u0415\u0441\u0442\u044c \u043f\u0440\u043e\u0431\u043b\u0435\u043c\u0430 \u0441 \u0437\u0430\u0433\u0440\u0443\u0437\u043a\u043e\u0439 \u0434\u0430\u043d\u043d\u044b\u0445';
const _kRetry = '\u041f\u043e\u0432\u0442\u043e\u0440\u0438\u0442\u044c';
const _kSignOutOfAccount = '\u0412\u044b\u0439\u0442\u0438 \u0438\u0437 \u0430\u043a\u043a\u0430\u0443\u043d\u0442\u0430';
const _kFailedLoadSession = '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0437\u0430\u0433\u0440\u0443\u0437\u0438\u0442\u044c \u0441\u0435\u0441\u0441\u0438\u044e.';
const _kAccountCreatedConfirm =
    '\u0410\u043a\u043a\u0430\u0443\u043d\u0442 \u0441\u043e\u0437\u0434\u0430\u043d. \u041f\u043e\u0434\u0442\u0432\u0435\u0440\u0434\u0438\u0442\u0435 email \u0438 \u0437\u0430\u0442\u0435\u043c \u0432\u043e\u0439\u0434\u0438\u0442\u0435 \u0432 \u0441\u0438\u0441\u0442\u0435\u043c\u0443.';
const _kCompanyCreatedContinue =
    '\u041a\u043e\u043c\u043f\u0430\u043d\u0438\u044f \u0441\u043e\u0437\u0434\u0430\u043d\u0430, \u043c\u043e\u0436\u043d\u043e \u043f\u0440\u043e\u0434\u043e\u043b\u0436\u0430\u0442\u044c \u0440\u0430\u0431\u043e\u0442\u0443.';
const _kInviteCreated = '\u041f\u0440\u0438\u0433\u043b\u0430\u0448\u0435\u043d\u0438\u0435 \u0441\u043e\u0437\u0434\u0430\u043d\u043e.';
const _kInviteCreatedWithCode =
    '\u041f\u0440\u0438\u0433\u043b\u0430\u0448\u0435\u043d\u0438\u0435 \u0441\u043e\u0437\u0434\u0430\u043d\u043e. \u041a\u043e\u0434 \u043f\u0440\u0438\u0433\u043b\u0430\u0448\u0435\u043d\u0438\u044f: {token}';
const _kAnErrorOccurred = '\u041f\u0440\u043e\u0438\u0437\u043e\u0448\u043b\u0430 \u043e\u0448\u0438\u0431\u043a\u0430.';
const _kChiefEngineer = '\u0413\u043b\u0430\u0432\u043d\u044b\u0439 \u0438\u043d\u0436\u0435\u043d\u0435\u0440';
const _kEngineer = '\u0418\u043d\u0436\u0435\u043d\u0435\u0440';
const _kInstaller = '\u041c\u043e\u043d\u0442\u0430\u0436\u043d\u0438\u043a';

final Map<String, Map<String, String>> _translations = {
  'en': {
    _kLanguage: 'Language',
    _kUser: 'User',
    _kCompany: 'Company',
    _kProfile: 'Profile',
    _kRefreshData: 'Refresh data',
    _kWorkAreas: 'Work areas',
    _kOwner: 'Owner',
    _kAdministrator: 'Administrator',
    _kEmployee: 'Employee',
    _kSignInTab: 'Sign in',
    _kSignUpTab: 'Sign up',
    _kEmployeeSignIn: 'Sign in for employees',
    _kUseWorkEmail:
        'Use your work email and password to access your company workspace.',
    _kWorkEmail: 'Work email',
    _kPassword: 'Password',
    _kResetPassword: 'Reset password',
    _kSignIn: 'Sign in',
    _kOwnerRegistration: 'Company owner sign up',
    _kCreateFirstCompanyAccount:
        'Create the first company account. After that you will be able to add employees.',
    _kYourName: 'Your name',
    _kPosition: 'Position',
    _kCompanyName: 'Company name',
    _kGoToSignIn: 'Go to sign in',
    _kCreateCompany: 'Create company',
    _kRequiredField: 'This field is required.',
    _kEnterEmail: 'Enter an email address.',
    _kEnterValidEmail: 'Enter a valid email address.',
    _kEnterPassword: 'Enter a password.',
    _kMin8: 'Minimum 8 characters.',
    _kAccountAlreadyExistsTry:
        'An account with this email already exists. Try signing in or resetting your password.',
    _kAccountAlreadyExistsGo:
        'An account with this email already exists. Go to sign in or reset your password.',
    _kFailedSignIn: 'Failed to sign in.',
    _kFailedCreateAccount: 'Failed to create the account.',
    _kEnterWorkEmailForReset:
        'Enter your work email. We will send you an email with a password reset link.',
    _kSendEmail: 'Send email',
    _kCancel: 'Cancel',
    _kRecoveryEmailSent:
        'We sent a password recovery email if an account with this email exists.',
    _kEnterEmailForRecovery: 'Enter an email to recover your password.',
    _kFailedSendRecoveryEmail: 'Failed to send the password recovery email.',
    _kSetNewPassword: 'Set a new password',
    _kRecoveryConfirmed:
        'The recovery link has been confirmed. You can now set a new password for the account.',
    _kNewPassword: 'New password',
    _kRepeatNewPassword: 'Repeat the new password',
    _kPasswordsMismatch: 'Passwords do not match.',
    _kSaveNewPassword: 'Save new password',
    _kExitRecoveryMode: 'Exit recovery mode',
    _kFailedUpdatePassword: 'Failed to update the password.',
    _kPasswordUpdated: 'Password updated.',
    _kEnterNewPassword: 'Enter a new password.',
    _kInfraManagement: 'Infrastructure management for companies and their teams',
    _kPlatformDescription:
        'Sign in to your company workspace, create the first organization, and prepare access for employees on one platform.',
    _kOneAccountPerCompany: 'One account per company',
    _kOwnerCreatesWorkspace:
        'The owner creates the workspace and then adds employees.',
    _kSupabaseSessions: 'Supabase sessions',
    _kAppRestoresSession:
        'The app automatically restores the active user session.',
    _kReadyForMultiTenant: 'Ready for multi-tenant',
    _kProfilesSeparated:
        'Profiles, companies, and employee roles are already separated at the database level.',
    _kSupabaseNotConfigured: 'Supabase is not configured yet',
    _kSupabaseDefineHelp:
        'Before running the app, pass two dart-define parameters: SUPABASE_URL and SUPABASE_ANON_KEY.',
    _kAppShowsSignIn:
        'After that, the app will show the sign-in screen and company onboarding.',
    _kCompleteCompanySetup: 'Complete company setup',
    _kSignedInAsButNoWorkspace:
        'You are signed in as {email}, but the company workspace has not been created yet.',
    _kEnterCompanyName: 'Enter the company name.',
    _kCreateWorkspace: 'Create workspace',
    _kFailedCompleteCompanySetup: 'Failed to complete company setup.',
    _kCompanyConnected: 'Company connected, the account is ready.',
    _kEmployeeProfile: 'Employee profile',
    _kPersonalData: 'Personal details',
    _kProfileDescription:
        'Here you can update the name and position. Email and role are read-only.',
    _kRoleInCompany: 'Role in company',
    _kEmployeeName: 'Employee name',
    _kEnterEmployeeName: 'Enter the employee name.',
    _kSaveProfile: 'Save profile',
    _kProfileUpdated: 'Profile updated.',
    _kFailedUpdateProfile: 'Failed to update the profile.',
    _kProblemLoadingData: 'There is a problem loading data',
    _kRetry: 'Retry',
    _kSignOutOfAccount: 'Sign out of the account',
    _kFailedLoadSession: 'Failed to load the session.',
    _kAccountCreatedConfirm:
        'Account created. Confirm your email and then sign in.',
    _kCompanyCreatedContinue:
        'The company has been created, you can continue working.',
    _kInviteCreated: 'Invitation created.',
    _kInviteCreatedWithCode: 'Invitation created. Invite code: {token}',
    _kAnErrorOccurred: 'An error occurred.',
    _kChiefEngineer: 'Chief Engineer',
    _kEngineer: 'Engineer',
    _kInstaller: 'Installer',
  },
  'es': {
    _kLanguage: 'Idioma',
    _kUser: 'Usuario',
    _kCompany: 'Empresa',
    _kProfile: 'Perfil',
    _kRefreshData: 'Actualizar datos',
    _kWorkAreas: 'Secciones de trabajo',
    _kOwner: 'Propietario',
    _kAdministrator: 'Administrador',
    _kEmployee: 'Empleado',
  },
  'ru': {},
  'zh': {
    _kLanguage: '\u8bed\u8a00',
    _kUser: '\u7528\u6237',
    _kCompany: '\u516c\u53f8',
    _kProfile: '\u8d44\u6599',
    _kRefreshData: '\u5237\u65b0\u6570\u636e',
    _kWorkAreas: '\u5de5\u4f5c\u533a\u57df',
    _kOwner: '\u6240\u6709\u8005',
    _kAdministrator: '\u7ba1\u7406\u5458',
    _kEmployee: '\u5458\u5de5',
  },
  'hi': {
    _kLanguage: '\u092d\u093e\u0937\u093e',
    _kUser: '\u0909\u092a\u092f\u094b\u0917\u0915\u0930\u094d\u0924\u093e',
    _kCompany: '\u0915\u0902\u092a\u0928\u0940',
    _kProfile: '\u092a\u094d\u0930\u094b\u095e\u093e\u0907\u0932',
    _kRefreshData: '\u0921\u0947\u091f\u093e \u0930\u0940\u095e\u094d\u0930\u0947\u0936 \u0915\u0930\u0947\u0902',
    _kWorkAreas: '\u0915\u093e\u0930\u094d\u092f \u0905\u0928\u0941\u092d\u093e\u0917',
    _kOwner: '\u092e\u093e\u0932\u093f\u0915',
    _kAdministrator: '\u092a\u094d\u0930\u0936\u093e\u0938\u0915',
    _kEmployee: '\u0915\u0930\u094d\u092e\u091a\u093e\u0930\u0940',
  },
  'ar': {
    _kLanguage: '\u0627\u0644\u0644\u063a\u0629',
    _kUser: '\u0627\u0644\u0645\u0633\u062a\u062e\u062f\u0645',
    _kCompany: '\u0627\u0644\u0634\u0631\u0643\u0629',
    _kProfile: '\u0627\u0644\u0645\u0644\u0641 \u0627\u0644\u0634\u062e\u0635\u064a',
    _kRefreshData: '\u062a\u062d\u062f\u064a\u062b \u0627\u0644\u0628\u064a\u0627\u0646\u0627\u062a',
    _kWorkAreas: '\u0623\u0642\u0633\u0627\u0645 \u0627\u0644\u0639\u0645\u0644',
    _kOwner: '\u0627\u0644\u0645\u0627\u0644\u0643',
    _kAdministrator: '\u0627\u0644\u0645\u0634\u0631\u0641',
    _kEmployee: '\u0627\u0644\u0645\u0648\u0638\u0641',
  },
};
