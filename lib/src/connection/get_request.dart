import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/base_api_url_config.dart';
import '../config/result_api.dart';
import '../cache/cache_manager.dart';
import '../cache/cache_type.dart';
import '../models/result_model.dart';
import '../utils/decode_json_isolate.dart';
import '../utils/debouncer.dart';
import '../utils/volt_log.dart';
import '../volt.dart';
import 'throw_http_exception.dart';

/// [GetRequest] is the main handler for HTTP GET operations.
///
/// It supports caching, debouncing, and automatic JSON decoding in isolates.
class GetRequest<T extends BaseApiUrlConfig> {
  final http.Client client;
  final CacheManager requestCache;
  final Map<String, Debouncer> debouncers;
  final Map<String, Completer<ResultApi>> activeRequests;
  final Map<String, String> lastDebounceParams;

  GetRequest(
      {http.Client? client,
      CacheManager? cache,
      Map<String, String>? lastDebounceParams,
      Map<String, Debouncer>? debouncers,
      Map<String, Completer<ResultApi>>? activeRequests})
      : client = client ?? http.Client(),
        requestCache = cache ?? CacheManager(),
        lastDebounceParams = lastDebounceParams ?? {},
        debouncers = debouncers ?? {},
        activeRequests = activeRequests ?? {};

  /// Performs a GET request with a built-in debounce mechanism.
  ///
  /// [delay] The time to wait before executing the request.
  /// [debounceKey] Optional custom key to identify this debounce group.
  ///
  /// Example:
  /// ```dart
  /// final result = await getRequest.getWithDebounce(config, 'search', queryParameters: {'q': 'flutter'});
  /// ```
  Future<ResultApi> getWithDebounce(
    T apiConfig,
    String endpoint, {
    Duration delay = const Duration(milliseconds: 500),
    Map<String, dynamic>? queryParameters,
    CacheType? type,
    bool cacheEnabled = false,
    Duration? ttl,
    Map<String, String>? personalizedHeader,
    String? cacheGroup,
    String? debounceKey,
  }) async {
    final baseUrl = apiConfig.resolveBaseUrl();
    final groupKey = debounceKey ?? 'DEBOUNCE_${baseUrl}_$endpoint';

    if (activeRequests.containsKey(groupKey)) {
      if (!activeRequests[groupKey]!.isCompleted) {
        activeRequests[groupKey]!.complete(ResultApi(isCancelled: true));
      }
      activeRequests.remove(groupKey);
    }

    final completer = Completer<ResultApi>();
    activeRequests[groupKey] = completer;

    debouncers
        .putIfAbsent(groupKey, () => Debouncer(delay: delay))
        .run(() async {
      try {
        final result = await get(
          apiConfig,
          endpoint,
          queryParameters: queryParameters,
          type: type,
          cacheEnabled: cacheEnabled,
          ttl: ttl,
          personalizedHeader: personalizedHeader,
          cancelPrevious: false,
          cacheGroup: cacheGroup,
        );
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      } finally {
        if (activeRequests[groupKey] == completer) {
          activeRequests.remove(groupKey);
        }
      }
    });

    return completer.future;
  }

  /// Executes a standard HTTP GET request.
  ///
  /// [cacheEnabled] If true, the request will use the local cache system.
  /// [cancelPrevious] If true, any ongoing request for the same URL will be cancelled.
  ///
  /// Example:
  /// ```dart
  /// final result = await getRequest.get(config, 'users');
  /// ```
  Future<ResultApi> get(
    T apiConfig,
    String endpoint, {
    Map<String, dynamic>? queryParameters,
    CacheType? type,
    bool cacheEnabled = false,
    bool readCache = true,
    Duration? ttl,
    Map<String, String>? personalizedHeader,
    bool cancelPrevious = false,
    String? cacheGroup,
    Duration? timeout,
  }) {
    final baseUrl = apiConfig.resolveBaseUrl();
    final requestKey = _generateKey('GET', baseUrl, endpoint, queryParameters);

    if (cancelPrevious) {
      activeRequests[requestKey]?.complete(ResultApi(isCancelled: true));
      activeRequests.remove(requestKey);
    }

    final completer = Completer<ResultApi>();
    activeRequests[requestKey] = completer;

    _executeGet(
      apiConfig: apiConfig,
      endpoint: endpoint,
      completer: completer,
      queryParameters: queryParameters,
      type: type,
      cacheEnabled: cacheEnabled,
      readCache: readCache,
      ttl: ttl,
      personalizedHeader: personalizedHeader,
      cacheGroup: cacheGroup,
      requestKey: requestKey,
      timeout: timeout,
    );

    return completer.future;
  }

  Map<String, dynamic>? _sanitizeParams(Map<String, dynamic>? params) {
    if (params == null) return null;
    return params.map((key, value) {
      if (value is Iterable) {
        return MapEntry(key, value.map((e) => e.toString()).toList());
      }
      return MapEntry(key, value.toString());
    });
  }

  Future<void> _executeGet({
    required T apiConfig,
    required String endpoint,
    required Completer<ResultApi> completer,
    required String requestKey,
    Map<String, dynamic>? queryParameters,
    CacheType? type,
    bool cacheEnabled = false,
    bool readCache = true,
    Duration? ttl,
    Map<String, String>? personalizedHeader,
    String? cacheGroup,
    Duration? timeout,
  }) async {
    try {
      final baseUrl = apiConfig.resolveBaseUrl();
      final token = await apiConfig.getToken();

      final sanitizedParams = _sanitizeParams(queryParameters);
      final uri = Uri.parse(baseUrl)
          .resolve(endpoint)
          .replace(queryParameters: sanitizedParams);
      final fullUrl = uri.toString();

      if (cacheEnabled && type != null && readCache) {
        final cached = await requestCache.get(
          type: type,
          token: token,
          endpoint: fullUrl,
          cacheGroup: cacheGroup,
          ttl: ttl,
        );
        if (cached != null) {
          VoltLog.d('GET Request (Cache Hit): $fullUrl');
          if (!completer.isCompleted) completer.complete(cached);
          return;
        }
      }

      if (completer.isCompleted) return;

      final headers = personalizedHeader ?? await apiConfig.getHeader();
      http.BaseRequest request = http.Request('GET', uri)
        ..headers.addAll(headers);

      for (var interceptor in Volt.interceptors) {
        request = await interceptor.onRequest(request);
      }

      VoltLog.logRequest(
        method: request.method,
        url: request.url.toString(),
        headers: request.headers,
      );

      final effectiveTimeout = timeout ?? Volt.timeout;
      final streamedResponse =
          await client.send(request).timeout(effectiveTimeout);
      var response = await http.Response.fromStream(streamedResponse);

      for (var interceptor in Volt.interceptors) {
        response = await interceptor.onResponse(response);
      }

      VoltLog.logResponse(
        url: request.url.toString(),
        statusCode: response.statusCode,
        body: response.body,
      );

      final resultApi = ResultApi(response: response);

      if (resultApi.isSuccess && cacheEnabled && type != null) {
        await requestCache.save(
          type: type == CacheType.memory ? CacheType.memory : CacheType.both,
          token: token,
          endpoint: fullUrl,
          cacheGroup: cacheGroup,
          data: resultApi,
        );
      }

      if (!resultApi.isSuccess) {
        throw ThrowHttpException.handle(resultApi);
      }

      if (!completer.isCompleted) completer.complete(resultApi);
    } catch (e) {
      VoltLog.e('GET Request Error: $endpoint', e);
      for (var interceptor in Volt.interceptors) {
        interceptor.onError(e);
      }

      final voltEx = ThrowHttpException.mapNativeException(e);

      if (voltEx is HttpNetworkException) {
        if (cacheEnabled && type != null) {
          final token = await apiConfig.getToken();
          final sanitizedParams = _sanitizeParams(queryParameters);
          final uri = Uri.parse(apiConfig.resolveBaseUrl())
              .resolve(endpoint)
              .replace(queryParameters: sanitizedParams);
          final cached = await requestCache.get(
            type: type,
            token: token,
            endpoint: uri.toString(),
            cacheGroup: cacheGroup,
            ttl: null,
          );
          if (cached != null) {
            VoltLog.w(
                'Network error, falling back to expired cache for $endpoint');
            if (!completer.isCompleted) completer.complete(cached);
            return;
          }
        }

        if (!completer.isCompleted) {
          completer.complete(ResultApi(response: null));
        }
      } else {
        if (!completer.isCompleted) completer.completeError(voltEx);
      }
    } finally {
      if (activeRequests[requestKey] == completer) {
        activeRequests.remove(requestKey);
      }
    }
  }

  /// Kept for backward compatibility. Fetches a model or a list of models.
  @Deprecated('Use getModelResult or getListResult for better type safety.')
  Future<dynamic> getModel<M>(
    T apiConfig,
    String endpoint,
    M Function(Map<String, dynamic>) parser, {
    Map<String, dynamic>? queryParameters,
    CacheType? type,
    bool cacheEnabled = false,
    bool asList = false,
    Duration? ttl,
    Map<String, String>? personalizedHeader,
    bool cancelPrevious = false,
    String? cacheGroup,
  }) async {
    if (asList) {
      final res = await getListResult<M>(
        apiConfig,
        endpoint,
        parser,
        queryParameters: queryParameters,
        type: type,
        cacheEnabled: cacheEnabled,
        ttl: ttl,
        personalizedHeader: personalizedHeader,
        cancelPrevious: cancelPrevious,
        cacheGroup: cacheGroup,
      );
      return res.model ?? <M>[];
    }

    final res = await getModelResult<M>(
      apiConfig,
      endpoint,
      parser,
      queryParameters: queryParameters,
      type: type,
      cacheEnabled: cacheEnabled,
      ttl: ttl,
      personalizedHeader: personalizedHeader,
      cancelPrevious: cancelPrevious,
      cacheGroup: cacheGroup,
    );
    return res.model;
  }

  /// Fetches a single model [M] and automatically parses it.
  ///
  /// Returns a [ResultModel] containing the data, raw response, or errors.
  ///
  /// Example:
  /// ```dart
  /// final result = await getRequest.getModelResult(config, 'profile', User.fromJson);
  /// if (result.hasData) print(result.model!.name);
  /// ```
  Future<ResultModel<M>> getModelResult<M>(
    T apiConfig,
    String endpoint,
    M Function(Map<String, dynamic>) parser, {
    Map<String, dynamic>? queryParameters,
    CacheType? type,
    bool cacheEnabled = false,
    Duration? ttl,
    Map<String, String>? personalizedHeader,
    bool cancelPrevious = false,
    String? cacheGroup,
  }) async {
    try {
      final result = await get(
        apiConfig,
        endpoint,
        queryParameters: queryParameters,
        type: type,
        cacheEnabled: cacheEnabled,
        readCache: true,
        ttl: ttl,
        personalizedHeader: personalizedHeader,
        cancelPrevious: cancelPrevious,
        cacheGroup: cacheGroup,
      );

      if (result.isCancelled) return ResultModel<M>(result: result);

      final content = result.bodyAsString;
      if (content == null || content.isEmpty) {
        return ResultModel<M>(result: result);
      }

      final model = await compute(decodeJsonInIsolate<M>, [content, parser]);
      return ResultModel<M>(model: model, result: result);
    } on VoltNetException catch (e) {
      return ResultModel<M>(error: e);
    } catch (e) {
      VoltLog.e('getModelResult Error', e);
      return ResultModel<M>(error: ThrowHttpException.mapNativeException(e));
    }
  }

  /// Fetches a list of models [M] and automatically parses it.
  ///
  /// Example:
  /// ```dart
  /// final result = await getRequest.getListResult(config, 'posts', Post.fromJson);
  /// ```
  Future<ResultModel<List<M>>> getListResult<M>(
    T apiConfig,
    String endpoint,
    M Function(Map<String, dynamic>) parser, {
    Map<String, dynamic>? queryParameters,
    CacheType? type,
    bool cacheEnabled = false,
    Duration? ttl,
    Map<String, String>? personalizedHeader,
    bool cancelPrevious = false,
    String? cacheGroup,
  }) async {
    try {
      final result = await get(
        apiConfig,
        endpoint,
        queryParameters: queryParameters,
        type: type,
        cacheEnabled: cacheEnabled,
        readCache: true,
        ttl: ttl,
        personalizedHeader: personalizedHeader,
        cancelPrevious: cancelPrevious,
        cacheGroup: cacheGroup,
      );

      if (result.isCancelled) {
        return ResultModel<List<M>>(result: result, model: []);
      }

      final content = result.bodyAsString;
      if (content == null || content.isEmpty) {
        return ResultModel<List<M>>(result: result, model: []);
      }

      final models =
          await compute(decodeJsonListInIsolate<M>, [content, parser]);
      return ResultModel<List<M>>(model: models, result: result);
    } on VoltNetException catch (e) {
      return ResultModel<List<M>>(error: e, model: []);
    } catch (e) {
      VoltLog.e('getListResult Error', e);
      return ResultModel<List<M>>(
          error: ThrowHttpException.mapNativeException(e), model: []);
    }
  }

  /// Fetches raw bytes from a URL. Useful for images or downloads.
  ///
  /// Example:
  /// ```dart
  /// final bytes = await getRequest.getBytes(config, 'https://example.com/img.png');
  /// ```
  Future<Uint8List> getBytes(
    T apiConfig,
    String url, {
    bool cacheEnabled = true,
    Map<String, String>? personalizedHeader,
  }) async {
    try {
      final uri = Uri.parse(url);
      final token = await apiConfig.getToken();

      if (cacheEnabled) {
        final cached = await requestCache.get(
          type: CacheType.disk,
          token: token,
          endpoint: url,
        );
        if (cached != null && cached.response != null) {
          return cached.response!.bodyBytes;
        }
      }

      final response = await client.get(uri,
          headers: personalizedHeader ?? await apiConfig.getHeader());
      final resultApi = ResultApi(response: response);

      if (resultApi.isSuccess && cacheEnabled) {
        await requestCache.save(
          type: CacheType.disk,
          token: token,
          endpoint: url,
          data: resultApi,
        );
      }

      if (!resultApi.isSuccess) {
        throw ThrowHttpException.handle(resultApi);
      }

      return response.bodyBytes;
    } catch (e) {
      throw ThrowHttpException.mapNativeException(e);
    }
  }

  String _generateKey(String method, String baseUrl, String endpoint,
      Map<String, dynamic>? params) {
    return '${method}_${baseUrl}_${endpoint}_${params?.toString()}';
  }
}
