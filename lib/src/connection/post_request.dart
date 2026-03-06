import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config/base_api_url_config.dart';
import '../config/result_api.dart';
import '../models/result_model.dart';
import '../models/volt_file.dart';
import '../cache/cache_manager.dart';
import '../offline/sync_queue_manager.dart';
import '../utils/decode_json_isolate.dart';
import '../utils/debouncer.dart';
import '../utils/volt_log.dart';
import '../volt.dart';
import 'throw_http_exception.dart';

/// [PostRequest] handles all HTTP POST operations with built-in resilience.
///
/// It supports multipart requests, offline synchronization, and batch operations.
class PostRequest<T extends BaseApiUrlConfig> {
  final http.Client client;
  final CacheManager requestCache;
  final SyncQueueManager syncQueue;
  final Map<String, Debouncer> debouncers;
  final Map<String, Completer<ResultApi>> activeRequests;

  PostRequest({
    http.Client? client,
    CacheManager? cache,
    SyncQueueManager? syncQueue,
  })  : client = client ?? http.Client(),
        requestCache = cache ?? CacheManager(),
        syncQueue = syncQueue ?? SyncQueueManager(),
        debouncers = {},
        activeRequests = {};

  /// Executes a standard HTTP POST request.
  ///
  /// [data] The payload to send. Can be a Map, List, or String.
  /// [isMultipart] Whether to send the request as `multipart/form-data`.
  /// [offlineSync] If true, the request will be queued for later if the network fails.
  ///
  /// Example:
  /// ```dart
  /// final result = await postRequest.post(config, endpoint: 'users', data: {'name': 'New User'});
  /// ```
  Future<ResultApi> post(
    T apiConfig, {
    String endpoint = '',
    dynamic data,
    bool isMultipart = false,
    bool offlineSync = true,
    Map<String, String>? personalizedHeader,
    Map<String, String>? extraHeaders,
    bool cancelPrevious = false,
    String? cacheGroup,
    Duration? timeout,
  }) {
    final url = Uri.parse(apiConfig.resolveBaseUrl()).resolve(endpoint);
    final requestKey = 'POST_${url.toString()}';

    if (cancelPrevious) {
      activeRequests[requestKey]?.complete(ResultApi(isCancelled: true));
      activeRequests.remove(requestKey);
    }

    final completer = Completer<ResultApi>();
    activeRequests[requestKey] = completer;

    _executePost(
      apiConfig: apiConfig,
      endpoint: endpoint,
      completer: completer,
      data: data,
      isMultipart: isMultipart,
      offlineSync: offlineSync,
      personalizedHeader: personalizedHeader,
      extraHeaders: extraHeaders,
      requestKey: requestKey,
      timeout: timeout,
    );

    return completer.future;
  }

  Future<void> _executePost({
    required T apiConfig,
    required String endpoint,
    required Completer<ResultApi> completer,
    required String requestKey,
    dynamic data,
    bool isMultipart = false,
    bool offlineSync = true,
    Map<String, String>? personalizedHeader,
    Map<String, String>? extraHeaders,
    Duration? timeout,
  }) async {
    final url = Uri.parse(apiConfig.resolveBaseUrl()).resolve(endpoint);
    try {
      final headers = personalizedHeader ?? await apiConfig.getHeader();
      if (extraHeaders != null) {
        headers.addAll(extraHeaders);
      }

      http.BaseRequest request;
      List<String>? voltFilePaths;

      if (isMultipart) {
        var multipartRequest = http.MultipartRequest('POST', url);
        multipartRequest.headers.addAll(headers);
        voltFilePaths = [];

        if (data is Map<String, dynamic>) {
          for (var entry in data.entries) {
            final value = entry.value;
            if (value is VoltFile) {
              multipartRequest.files.add(await value.toMultipartFile());
              voltFilePaths.add(value.path);
            } else if (value is Iterable<VoltFile>) {
              for (var file in value) {
                multipartRequest.files.add(await file.toMultipartFile());
                voltFilePaths.add(file.path);
              }
            } else if (value is http.MultipartFile) {
              multipartRequest.files.add(value);
            } else {
              multipartRequest.fields[entry.key] = value.toString();
            }
          }
        }
        request = multipartRequest;
      } else {
        final postRequest = http.Request('POST', url);
        postRequest.headers.addAll(headers);
        if (data != null) {
          postRequest.body = jsonEncode(data);
        }
        request = postRequest;
      }

      for (var interceptor in Volt.interceptors) {
        request = await interceptor.onRequest(request);
      }

      VoltLog.logRequest(
        method: request.method,
        url: request.url.toString(),
        headers: request.headers,
        body: isMultipart
            ? (voltFilePaths?.isNotEmpty == true
                ? 'Multipart files: $voltFilePaths'
                : null)
            : data,
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
      if (!resultApi.isSuccess) throw ThrowHttpException.handle(resultApi);
      if (!completer.isCompleted) completer.complete(resultApi);
    } catch (e) {
      VoltLog.e('POST Request Error: $endpoint', e);
      for (var interceptor in Volt.interceptors) {
        interceptor.onError(e);
      }

      final voltEx = ThrowHttpException.mapNativeException(e);

      if (offlineSync && voltEx is HttpNetworkException) {
        VoltLog.w('Network failure. Enqueuing POST (Offline Sync)');

        final headers = personalizedHeader ?? await apiConfig.getHeader();
        Map<String, dynamic> cleanData = {};
        List<String> filePaths = [];

        if (isMultipart && data is Map<String, dynamic>) {
          data.forEach((k, v) {
            if (v is VoltFile) {
              filePaths.add(v.path);
            } else if (v is Iterable<VoltFile>) {
              filePaths.addAll(v.map((f) => f.path));
            } else if (v is! http.MultipartFile) {
              cleanData[k] = v;
            }
          });
        } else {
          cleanData = data is Map<String, dynamic> ? data : {};
        }

        await syncQueue.enqueue(
          endpoint: url.toString(),
          method: 'POST',
          body: isMultipart ? cleanData : data,
          headers: headers,
          isMultipart: isMultipart,
          filePaths: filePaths.isNotEmpty ? filePaths : null,
        );

        if (!completer.isCompleted) {
          completer.complete(ResultApi(isPending: true));
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

  /// Executes a batch of requests sequentially.
  ///
  /// If [rollbackOnFailure] is true, it will stop and call [onRollback] on any error.
  ///
  /// Example:
  /// ```dart
  /// await postRequest.resilientBatch([
  ///   ({extraHeaders}) => postRequest.post(config, endpoint: 'step1', extraHeaders: extraHeaders),
  ///   ({extraHeaders}) => postRequest.post(config, endpoint: 'step2', extraHeaders: extraHeaders),
  /// ]);
  /// ```
  Future<List<ResultApi>> resilientBatch(
    List<Future<ResultApi> Function({Map<String, String>? extraHeaders})>
        requests, {
    String? idempotencyKey,
    bool rollbackOnFailure = true,
    Future<void> Function(List<ResultApi>)? onRollback,
  }) async {
    List<ResultApi> results = [];
    final effectiveIdempotencyKey = idempotencyKey ?? const Uuid().v4();

    try {
      for (var i = 0; i < requests.length; i++) {
        final request = requests[i];
        ResultApi result;
        try {
          result = await request(extraHeaders: {
            'Idempotency-Key': '$effectiveIdempotencyKey-$i',
          });
        } catch (e) {
          if (rollbackOnFailure) await _handleBatchFailure(results, onRollback);
          throw VoltNetException('Batch failed at step ${i + 1}. Error: $e');
        }
        if (!result.isSuccess) {
          if (rollbackOnFailure) await _handleBatchFailure(results, onRollback);
          throw VoltNetException('Batch failed at step ${i + 1}',
              statusCode: result.statusCode);
        }
        results.add(result);
      }
      return results;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _handleBatchFailure(List<ResultApi> successfulResults,
      Future<void> Function(List<ResultApi>)? onRollback) async {
    if (onRollback != null) await onRollback(successfulResults);
  }

  /// Performs a POST request with a built-in debounce mechanism.
  ///
  /// Example:
  /// ```dart
  /// await postRequest.postWithDebounce(config, endpoint: 'save', data: {'val': 1});
  /// ```
  Future<ResultApi> postWithDebounce(
    T apiConfig, {
    String endpoint = '',
    dynamic data,
    Duration delay = const Duration(milliseconds: 500),
    bool isMultipart = false,
    bool offlineSync = true,
    Map<String, String>? personalizedHeader,
    String? cacheGroup,
    String? debounceKey,
    Duration? timeout,
  }) async {
    final baseUrl = apiConfig.resolveBaseUrl();
    final groupKey = debounceKey ?? 'DEBOUNCE_POST_${baseUrl}_$endpoint';
    if (activeRequests.containsKey(groupKey) &&
        !activeRequests[groupKey]!.isCompleted) {
      activeRequests[groupKey]!.complete(ResultApi(isCancelled: true));
    }
    final completer = Completer<ResultApi>();
    activeRequests[groupKey] = completer;
    debouncers
        .putIfAbsent(groupKey, () => Debouncer(delay: delay))
        .run(() async {
      try {
        final result = await post(apiConfig,
            endpoint: endpoint,
            data: data,
            isMultipart: isMultipart,
            offlineSync: offlineSync,
            personalizedHeader: personalizedHeader,
            timeout: timeout);
        if (!completer.isCompleted) completer.complete(result);
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    });
    return completer.future;
  }

  /// Executes a POST request and automatically parses the response into model [M].
  ///
  /// Example:
  /// ```dart
  /// final result = await postRequest.postModel(config, 'create', User.fromJson, data: {...});
  /// ```
  Future<ResultModel<M>> postModel<M>(
    T apiConfig,
    String endpoint,
    M Function(Map<String, dynamic>) parser, {
    dynamic data,
    bool isMultipart = false,
    bool offlineSync = true,
    Map<String, String>? personalizedHeader,
    bool cancelPrevious = false,
    String? cacheGroup,
    Duration? timeout,
  }) async {
    try {
      final resultApi = await post(apiConfig,
          endpoint: endpoint,
          data: data,
          isMultipart: isMultipart,
          offlineSync: offlineSync,
          personalizedHeader: personalizedHeader,
          cancelPrevious: cancelPrevious,
          cacheGroup: cacheGroup,
          timeout: timeout);
      if (resultApi.isCancelled) return ResultModel<M>(result: resultApi);
      final String? content = resultApi.bodyAsString;
      if (content == null || !resultApi.isSuccess) {
        return ResultModel<M>(result: resultApi);
      }
      final model = await compute(decodeJsonInIsolate<M>, [content, parser]);
      return ResultModel<M>(model: model, result: resultApi);
    } catch (e) {
      return ResultModel<M>(error: ThrowHttpException.mapNativeException(e));
    }
  }
}
