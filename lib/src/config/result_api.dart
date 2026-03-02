import 'dart:convert';

import 'package:http/http.dart';

class ResultApi {
  final Map<String, dynamic>? body;
  final Response? response;
  final bool isPending; // Nova flag para requisições offline-first

  ResultApi({this.body, this.response, this.isPending = false});

  int get statusCode => response?.statusCode ?? 0;

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

  Map<String, dynamic>? get jsonBody {
    if (body != null) return body;
    final source = bodyAsString;
    if (source != null) {
      try {
        return jsonDecode(source) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  bool get isSuccess =>
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

  bool get isNetworkError => response == null && body == null;
}
