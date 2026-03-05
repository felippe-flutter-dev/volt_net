import 'dart:async';
import 'package:http/http.dart' as http;

import '../config/base_api_url_config.dart';
import '../config/result_api.dart';
import '../cache/cache_manager.dart';
import '../offline/sync_queue_manager.dart';
import '../utils/volt_log.dart';
import '../volt.dart';
import 'throw_http_exception.dart';

/// [DeleteRequest] handles HTTP DELETE operations with offline sync support.
class DeleteRequest<T extends BaseApiUrlConfig> {
  final http.Client client;
  final CacheManager requestCache;

  DeleteRequest({http.Client? client, CacheManager? cache})
      : client = client ?? http.Client(),
        requestCache = cache ?? CacheManager();

  Future<ResultApi> delete(
    T apiConfig, {
    String endpoint = '',
    bool offlineSync = true,
    Map<String, String>? personalizedHeader,
    Duration? timeout,
  }) async {
    final url = Uri.parse(apiConfig.resolveBaseUrl()).resolve(endpoint);
    try {
      final headers = personalizedHeader ?? await apiConfig.getHeader();

      var request = http.Request('DELETE', url);
      request.headers.addAll(headers);

      // Apply interceptors
      http.BaseRequest finalRequest = request;
      for (var interceptor in Volt.interceptors) {
        finalRequest = await interceptor.onRequest(finalRequest);
      }

      VoltLog.d('DELETE Request: ${finalRequest.url}');

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
        VoltLog.w('Network failure. Enqueuing DELETE for $endpoint');
        final headers = personalizedHeader ?? await apiConfig.getHeader();
        await SyncQueueManager().enqueue(
          endpoint: url.toString(),
          method: 'DELETE',
          body: null,
          headers: headers,
        );
        return ResultApi(isPending: true);
      } else {
        rethrow;
      }
    }
  }
}
