import 'package:volt_net/src/config/result_api.dart';

class ApiException implements Exception {
  final int statusCode;
  final String? body;
  final String? errorMessage;

  ApiException({required this.statusCode, this.body, this.errorMessage});

  @override
  String toString() {
    final msg = errorMessage ?? body ?? 'Unknown error';
    return 'ApiException: HTTP $statusCode - $msg';
  }
}

class ThrowHttpException {
  static Never handle(ResultApi resultApi) {
    final Map<int, String> knownErrors = {
      400: 'Bad Request',
      401: 'Unauthorized',
      403: 'Forbidden',
      404: 'Not Found',
      422: 'Unprocessable Entity',
      429: 'Too Many Requests',
      500: 'Internal Server Error',
      502: 'Bad Gateway',
      503: 'Service Unavailable',
    };

    final customMessage = knownErrors[resultApi.statusCode];

    throw ApiException(
      statusCode: resultApi.statusCode,
      body: resultApi.bodyAsString,
      errorMessage: customMessage,
    );
  }
}
