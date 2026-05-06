import 'product_presentation_launcher_stub.dart'
    if (dart.library.html) 'product_presentation_launcher_web.dart';

Future<bool> openProductPresentation(String languageCode) {
  return openProductPresentationPage(languageCode);
}
