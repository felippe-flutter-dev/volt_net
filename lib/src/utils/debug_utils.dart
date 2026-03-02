import 'package:flutter/foundation.dart';

class DebugUtils {
  static void printUrl({
    required String method,
    required String url,
    Map<String, String>? headers,
    String? body,
  }) {
    debugPrint('╔══════════════════════════════════════════');
    debugPrint('║ REQUEST: $method $url');
    if (headers != null && headers.isNotEmpty) {
      debugPrint('║ Headers:');
      headers.forEach((key, value) {
        debugPrint('║   $key: $value');
      });
    }
    if (body != null && body.isNotEmpty) {
      debugPrint('║ Body:');
      debugPrint('║   $body');
    }
    debugPrint('╚══════════════════════════════════════════');
  }

  static String generateCurl({
    required String method,
    required String url,
    Map<String, String>? headers,
    String? body,
  }) {
    final buffer = StringBuffer('curl -X $method "$url"');

    if (headers != null && headers.isNotEmpty) {
      headers.forEach((key, value) {
        buffer.write(' \\\n  -H "$key: $value"');
      });
    }

    if (body != null && body.isNotEmpty) {
      final escapedBody = body.replaceAll('"', '\\"');
      buffer.write(' \\\n  -d "$escapedBody"');
    }

    return buffer.toString();
  }

  static void printCurl({
    required String method,
    required String url,
    Map<String, String>? headers,
    String? body,
  }) {
    final curl = generateCurl(
      method: method,
      url: url,
      headers: headers,
      body: body,
    );
    debugPrint('╔════════════════ CURL PARA POSTMAN/TERMINAL ════════════════');
    debugPrint(curl);
    debugPrint('╚══════════════════════════════════════════════════════════');
  }
}
