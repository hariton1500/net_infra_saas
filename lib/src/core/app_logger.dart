import 'package:flutter/foundation.dart';

String normalizeErrorText(
  Object? value, {
  String fallback = 'Something went wrong.',
}) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) {
    return fallback;
  }

  final hasCyrillic = text.runes.any(
    (codeUnit) => codeUnit >= 0x0400 && codeUnit <= 0x04FF,
  );
  if (hasCyrillic) {
    final lower = text.toLowerCase();
    if (lower.contains('clientexception') || lower.contains('uri=')) {
      return 'Network request failed. Check your internet connection and try again.';
    }
    return fallback;
  }

  return text;
}

void logUserFacingError(
  String message, {
  String? source,
  Object? error,
  StackTrace? stackTrace,
}) {
  final scope = source == null || source.isEmpty ? 'app' : source;
  debugPrint('[ERROR][$scope] ${normalizeErrorText(message)}');

  if (error != null) {
    debugPrint('[ERROR][$scope][raw] ${normalizeErrorText(error)}');
  }

  if (stackTrace != null) {
    debugPrintStack(stackTrace: stackTrace, label: '[ERROR][$scope][stack]');
  }
}
