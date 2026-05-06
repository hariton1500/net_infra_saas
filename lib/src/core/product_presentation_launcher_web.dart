import 'dart:js_interop';

@JS('window.location.assign')
external void _assignLocation(JSString url);

Future<bool> openProductPresentationPage(String languageCode) async {
  final normalizedLanguage = languageCode == 'ru' ? 'ru' : 'en';
  _assignLocation('product_presentation.html?lang=$normalizedLanguage'.toJS);
  return true;
}
