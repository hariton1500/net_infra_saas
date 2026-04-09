import 'package:flutter/foundation.dart';

void logUserFacingError(
  String message, {
  String? source,
  Object? error,
  StackTrace? stackTrace,
}) {
  final scope = source == null || source.isEmpty ? 'app' : source;
  debugPrint('[ERROR][$scope] $message');

  if (error != null) {
    debugPrint('[ERROR][$scope][raw] $error');
  }

  if (stackTrace != null) {
    debugPrintStack(stackTrace: stackTrace, label: '[ERROR][$scope][stack]');
  }
}
