import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../volt.dart';
import 'debug_utils.dart';

enum VoltLogLevel { debug, info, warning, error }

/// Enterprise-grade logger for VoltNet.
class VoltLog {
  static void d(String message) => _log(VoltLogLevel.debug, message);
  static void i(String message) => _log(VoltLogLevel.info, message);
  static void w(String message) => _log(VoltLogLevel.warning, message);
  static void e(String message, [dynamic error, StackTrace? stackTrace]) {
    _log(VoltLogLevel.error, message);
    if (error != null) debugPrint('║ Error detail: $error');
    if (stackTrace != null) debugPrint('║ Stack trace: $stackTrace');
  }

  /// Specialized method to log HTTP requests using DebugUtils.
  static void logRequest({
    required String method,
    required String url,
    Map<String, String>? headers,
    dynamic body,
  }) {
    if (!Volt.logging) return;

    String? bodyString;
    if (body != null) {
      try {
        bodyString = body is String ? body : jsonEncode(body);
      } catch (_) {
        bodyString = body.toString();
      }
    }

    DebugUtils.printUrl(
      method: method,
      url: url,
      headers: headers,
      body: bodyString,
    );

    DebugUtils.printCurl(
      method: method,
      url: url,
      headers: headers,
      body: bodyString,
    );
  }

  /// Specialized method to log HTTP responses.
  static void logResponse({
    required String url,
    required int statusCode,
    required String body,
  }) {
    if (!Volt.logging) return;

    debugPrint('╔════════════════ RESPONSE ════════════════');
    debugPrint('║ URL: $url');
    debugPrint('║ Status Code: $statusCode');
    debugPrint('║ Body:');
    debugPrint('║   $body');
    debugPrint('╚══════════════════════════════════════════');
  }

  static void _log(VoltLogLevel level, String message) {
    if (!Volt.logging && level != VoltLogLevel.error) return;

    final timestamp = DateTime.now().toIso8601String();
    final prefix = '[VoltNet][${level.name.toUpperCase()}][$timestamp]';
    debugPrint('$prefix $message');
  }
}
