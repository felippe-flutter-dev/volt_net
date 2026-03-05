import 'dart:async';
import 'package:http/http.dart' as http;

/// Interface for VoltNet Interceptors.
/// Allows modifying requests before they are sent and responses after they are received.
abstract class VoltInterceptor {
  /// Called before the request is sent.
  FutureOr<http.BaseRequest> onRequest(http.BaseRequest request) => request;

  /// Called after a response is received.
  FutureOr<http.Response> onResponse(http.Response response) => response;

  /// Called when an error occurs during the request.
  FutureOr<void> onError(dynamic error) {}
}
