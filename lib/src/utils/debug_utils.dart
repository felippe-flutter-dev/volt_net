import 'package:flutter/foundation.dart';

class DebugUtils {
  /// Prints the request URL, method, headers, and body in a structured format.
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

  /// Generates a CURL command string for the given request parameters.
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

  /// Prints the CURL command for the request.
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
    debugPrint('╔════════════════ CURL ════════════════');
    debugPrint(curl);
    debugPrint('╚══════════════════════════════════════');
  }
}
