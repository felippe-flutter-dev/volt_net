import 'dart:convert';
import 'package:http/http.dart';

/// Represents the raw result of an API request.
class ResultApi {
  /// Optional body map if provided directly.
  final Map<String, dynamic>? body;

  /// The raw HTTP [Response] from the server.
  final Response? response;

  /// Whether the request is still pending (offline queue).
  final bool isPending;

  /// Whether the request was cancelled by a newer request (Race Condition).
  final bool isCancelled;

  ResultApi({
    this.body,
    this.response,
    this.isPending = false,
    this.isCancelled = false,
  });

  /// The HTTP status code of the response.
  int get statusCode => response?.statusCode ?? 0;

  /// Returns the response body as a [String].
  String? get bodyAsString {
    if (body != null && body!.isNotEmpty) {
      return jsonEncode(body);
    }

    if (response != null) {
      final b = response!.body;
      if (b.isNotEmpty && b.trim().toLowerCase() != 'null') {
        return b;
      }
    }

    return null;
  }

  /// Returns the decoded JSON body.
  ///
  /// Can be a [Map<String, dynamic>] or a [List<dynamic>].
  dynamic get jsonBody {
    if (body != null) return body;
    final source = bodyAsString;
    if (source != null) {
      try {
        return jsonDecode(source);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// True if the status code is in the 200-299 range and not cancelled.
  bool get isSuccess =>
      !isCancelled &&
      response != null &&
      response!.statusCode >= 200 &&
      response!.statusCode < 300;

  bool get isClientError =>
      response != null &&
      response!.statusCode >= 400 &&
      response!.statusCode < 500;

  bool get isServerError =>
      response != null &&
      response!.statusCode >= 500 &&
      response!.statusCode < 600;

  bool get isNetworkError => response == null && body == null && !isCancelled;
}
