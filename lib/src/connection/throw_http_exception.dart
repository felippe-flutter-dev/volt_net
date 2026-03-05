import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/result_api.dart';

/// Base class for all VoltNet exceptions.
class VoltNetException implements Exception {
  final int? statusCode;
  final String message;
  final String? body;

  VoltNetException(this.message, {this.statusCode, this.body});

  @override
  String toString() => 'VoltNetException [$statusCode]: $message ${body ?? ""}';
}

/// Client-side errors (4xx).
class HttpClientException extends VoltNetException {
  HttpClientException(super.message, int statusCode, {super.body})
      : super(statusCode: statusCode);
}

/// Server-side errors (5xx).
class HttpServerException extends VoltNetException {
  HttpServerException(super.message, int statusCode, {super.body})
      : super(statusCode: statusCode);
}

/// Connectivity and Network errors (Timeout, DNS, Socket).
class HttpNetworkException extends VoltNetException {
  HttpNetworkException(super.message) : super(statusCode: 0);
}

/// Authentication errors (401, 403).
class HttpAuthException extends VoltNetException {
  HttpAuthException(super.message, int statusCode, {super.body})
      : super(statusCode: statusCode);
}

class ThrowHttpException {
  /// Throws the appropriate exception based on the HTTP status code.
  static Never handle(ResultApi resultApi) {
    final code = resultApi.statusCode;
    final body = resultApi.bodyAsString;
    final message = _getStandardMessage(code);

    if (code == 401 || code == 403) {
      throw HttpAuthException(message, code, body: body);
    }

    if (code >= 400 && code < 500) {
      throw HttpClientException(message, code, body: body);
    }

    if (code >= 500) {
      throw HttpServerException(message, code, body: body);
    }

    throw VoltNetException(body ?? 'Unexpected error', statusCode: code);
  }

  static String _getStandardMessage(int code) {
    return switch (code) {
      400 => 'Bad Request',
      401 => 'Unauthorized',
      403 => 'Forbidden',
      404 => 'Not Found',
      422 => 'Unprocessable Entity',
      429 => 'Too Many Requests (Rate Limit)',
      500 => 'Internal Server Error',
      503 => 'Service Unavailable',
      _ => 'HTTP Error $code',
    };
  }

  /// Maps native Dart/HTTP exceptions to VoltNet exception types.
  static VoltNetException mapNativeException(Object error) {
    if (error is VoltNetException) {
      return error;
    }
    if (error is SocketException) {
      return HttpNetworkException('No internet connection (SocketException)');
    }
    if (error is HttpException) {
      return HttpNetworkException('HTTP protocol error');
    }
    if (error is HandshakeException) {
      return HttpNetworkException('Security failure (SSL/TLS Handshake)');
    }
    if (error is TimeoutException) {
      return HttpNetworkException('The request timed out');
    }
    if (error is http.ClientException) {
      return HttpNetworkException('Communication failure: ${error.message}');
    }

    return VoltNetException('Unexpected error: $error');
  }
}
