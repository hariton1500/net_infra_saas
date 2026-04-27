import 'strings.dart';

String tr(String key, [Map<String, String> params = const {}]) {
  var value = AppStrings.lookup(key);
  for (final entry in params.entries) {
    value = value.replaceAll('{${entry.key}}', entry.value);
  }
  return value;
}
