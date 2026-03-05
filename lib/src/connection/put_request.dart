import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/base_api_url_config.dart';
import '../config/result_api.dart';
import '../cache/cache_manager.dart';
import '../offline/sync_queue_manager.dart';
import '../utils/volt_log.dart';
import '../volt.dart';
import 'throw_http_exception.dart';

/// [PutRequest] handles HTTP PUT operations with offline sync support.
class PutRequest<T extends BaseApiUrlConfig> {
  final http.Client client;
  final CacheManager requestCache;

  PutRequest({http.Client? client, CacheManager? cache})
      : client = client ?? http.Client(),
        requestCache = cache ?? CacheManager();

  Future<ResultApi> put(
    T apiConfig, {
    String endpoint = '',
    dynamic data,
    bool offlineSync = true,
    Map<String, String>? personalizedHeader,
    Duration? timeout,
  }) async {
    final url = Uri.parse(apiConfig.resolveBaseUrl()).resolve(endpoint);
    try {
      final headers = personalizedHeader ?? await apiConfig.getHeader();

      var request = http.Request('PUT', url);
      request.headers.addAll(headers);
      if (data != null) {
        request.body = jsonEncode(data);
      }

      // Apply interceptors
      http.BaseRequest finalRequest = request;
      for (var interceptor in Volt.interceptors) {
        finalRequest = await interceptor.onRequest(finalRequest);
      }

      VoltLog.d('PUT Request: ${finalRequest.url}');

      final effectiveTimeout = timeout ?? Volt.timeout;
      final streamedResponse =
          await client.send(finalRequest).timeout(effectiveTimeout);
      var response = await http.Response.fromStream(streamedResponse);

      // Apply interceptors to response
      for (var interceptor in Volt.interceptors) {
        response = await interceptor.onResponse(response);
      }

      final resultApi = ResultApi(response: response);

      if (!resultApi.isSuccess) {
        throw ThrowHttpException.handle(resultApi);
      }

      return resultApi;
    } catch (e) {
      for (var interceptor in Volt.interceptors) {
        interceptor.onError(e);
      }

      final voltEx = ThrowHttpException.mapNativeException(e);

      if (offlineSync && voltEx is HttpNetworkException) {
        VoltLog.w('Network failure. Enqueuing PUT for $endpoint');
        final headers = personalizedHeader ?? await apiConfig.getHeader();
        await SyncQueueManager().enqueue(
          endpoint: url.toString(),
          method: 'PUT',
          body: data,
          headers: headers,
        );
        return ResultApi(isPending: true);
      } else {
        rethrow;
      }
    }
  }
}
