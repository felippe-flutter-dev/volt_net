import 'dart:async';
import 'package:volt_net/volt_net.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:volt_net/src/utils/decode_json_isolate.dart';

class GetRequest<T extends BaseApiUrlConfig> {
  final http.Client client;
  final CacheManager requestCache;

  GetRequest({http.Client? client, CacheManager? cache})
      : client = client ?? http.Client(),
        requestCache = cache ?? CacheManager();

  Future<ResultApi> get(
    T apiConfig,
    String endpoint, {
    Map<String, dynamic>? queryParameters,
    CacheType? type,
    bool cacheEnabled = false,
    bool readCache = true,
    Duration? ttl,
    Map<String, String>? personalizedHeader,
  }) async {
    final token = await apiConfig.getToken();

    // Construção inteligente da URI com query parameters
    final baseUrl = apiConfig.resolveBaseUrl();
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final cleanEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';

    final uri = Uri.parse(cleanBaseUrl + cleanEndpoint).replace(
      queryParameters: queryParameters?.map((key, value) {
        // Converte listas para o formato que APIs como MangaDex esperam (ex: lang[]=pt)
        if (value is Iterable){
          return MapEntry(key, value.map((e) => e.toString()).toList());}
        return MapEntry(key, value.toString());
      }),
    );

    final fullUrl = uri.toString();

    if (cacheEnabled && type != null && readCache) {
      final cached = await requestCache.get(
        type: type,
        token: token,
        endpoint: fullUrl, // Usamos a URL COMPLETA como chave agora
        ttl: ttl,
      );
      if (cached != null) return cached;
    }

    DebugUtils.printUrl(
      method: 'GET',
      url: fullUrl,
      headers: personalizedHeader ?? await apiConfig.getHeader(),
    );

    final response = await client.get(
      uri,
      headers: personalizedHeader ?? await apiConfig.getHeader(),
    );

    final resultApi = ResultApi(response: response);

    if (resultApi.isSuccess && cacheEnabled && type != null) {
      await requestCache.save(
        type: type == CacheType.memory ? CacheType.memory : CacheType.both,
        token: token,
        endpoint: fullUrl, // Salva com a URL completa (incluindo offset/limit)
        data: resultApi,
      );
    }

    if (!resultApi.isSuccess) {
      throw ThrowHttpException.handle(resultApi);
    }

    return resultApi;
  }

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
  }) async {
    final token = await apiConfig.getToken();

    // Resolve a URL completa para a chave de cache
    final baseUrl = apiConfig.resolveBaseUrl();
    final uri = Uri.parse(baseUrl + endpoint).replace(
        queryParameters:
            queryParameters?.map((k, v) => MapEntry(k, v.toString())));
    final fullUrl = uri.toString();

    bool shouldReadCacheInGet = true;

    if (cacheEnabled && type != null) {
      try {
        final cached = await requestCache.get(
          type: type,
          token: token,
          endpoint: fullUrl,
          ttl: ttl,
        );
        if (cached != null) {
          if (asList) {
            return await compute(
                decodeJsonListInIsolate<M>, [cached.bodyAsString, parser]);
          }
          return await compute(
              decodeJsonInIsolate<M>, [cached.bodyAsString, parser]);
        }
      } catch (e) {
        shouldReadCacheInGet = false;
        debugPrint('EcoloteNetwork: Cache corrompido para $fullUrl');
      }
    }

    final result = await get(
      apiConfig,
      endpoint,
      queryParameters: queryParameters,
      type: type,
      cacheEnabled: cacheEnabled,
      readCache: shouldReadCacheInGet,
      ttl: ttl,
      personalizedHeader: personalizedHeader,
    );

    if (asList) {
      return await compute(decodeJsonListInIsolate<M>, [
        result.bodyAsString,
        parser,
      ]);
    }

    return await compute(decodeJsonInIsolate<M>, [result.bodyAsString, parser]);
  }

  Future<Uint8List> getBytes(
    T apiConfig,
    String url, {
    bool cacheEnabled = true,
    Map<String, String>? personalizedHeader,
  }) async {
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

    // Usar os headers da config ou personalizados (evita bloqueio de User-Agent)
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
  }
}
