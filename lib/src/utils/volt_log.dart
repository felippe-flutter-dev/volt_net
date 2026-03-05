import 'package:flutter/foundation.dart';

enum VoltLogLevel { debug, info, warning, error }

/// Enterprise-grade logger for VoltNet.
class VoltLog {
  static void d(String message) => _log(VoltLogLevel.debug, message);
  static void i(String message) => _log(VoltLogLevel.info, message);
  static void w(String message) => _log(VoltLogLevel.warning, message);
  static void e(String message, [dynamic error, StackTrace? stackTrace]) {
    _log(VoltLogLevel.error, message);
    if (error != null) debugPrint('Error detail: $error');
    if (stackTrace != null) debugPrint('Stack trace: $stackTrace');
  }

  static void _log(VoltLogLevel level, String message) {
    final timestamp = DateTime.now().toIso8601String();
    final prefix = '[VoltNet][${level.name.toUpperCase()}][$timestamp]';
    debugPrint('$prefix $message');
  }
}
