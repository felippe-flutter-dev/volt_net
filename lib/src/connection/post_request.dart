import 'dart:convert';

import 'package:volt_net/volt_net.dart';
import 'package:volt_net/src/utils/decode_json_isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PostRequest<T extends BaseApiUrlConfig> {
  final http.Client client;
  final CacheManager requestCache;

  PostRequest({http.Client? client, CacheManager? cache})
      : client = client ?? http.Client(),
        requestCache = cache ?? CacheManager();

  Future<ResultApi> post(
    T apiConfig, {
    String endpoint = '',
    dynamic data,
    bool isMultipart = false,
    bool offlineSync = true, // Permite desativar a fila offline se desejar
    Map<String, String>? personalizedHeader,
    String? personalizedToken,
  }) async {
    final url = Uri.parse(apiConfig.resolveBaseUrl()).resolve(endpoint);
    final headers = personalizedHeader ?? await apiConfig.getHeader();

    try {
      http.Response response;

      if (isMultipart) {
        // ... (lógica multipart inalterada)
        var request = http.MultipartRequest('POST', url);
        request.headers.addAll(headers);

        if (data is Map<String, dynamic>) {
          for (var entry in data.entries) {
            final value = entry.value;
            if (value is http.MultipartFile) {
              request.files.add(value);
            } else if (value is Iterable<http.MultipartFile>) {
              request.files.addAll(value);
            } else {
              request.fields[entry.key] = value.toString();
            }
          }
        } else if (data is http.MultipartRequest) {
          request = data;
        }

        final streamedResponse = await client.send(request);
        response = await http.Response.fromStream(streamedResponse);
      } else {
        final bodyJson = data != null ? jsonEncode(data) : null;
        response = await client.post(url, headers: headers, body: bodyJson);
      }

      final resultApi = ResultApi(response: response);

      if (!resultApi.isSuccess) {
        throw ThrowHttpException.handle(resultApi);
      }

      return resultApi;
    } on http.ClientException {
      if (offlineSync && !isMultipart) {
        await SyncQueueManager().enqueue(
          endpoint: url.toString(),
          method: 'POST',
          body: data,
          headers: headers,
        );
        return ResultApi(isPending: true);
      }
      rethrow;
    } catch (e) {
      debugPrint('VoltNet POST ERROR: $e');
      rethrow;
    }
  }

  // Adicionei <M> no retorno e permiti que seja nulo (M?) para casos de 204
  Future<ResultModel<M>> postModel<M>(
    T apiConfig,
    String endpoint,
    M Function(Map<String, dynamic>) parser, {
    dynamic data,
    bool isMultipart = false,
    Map<String, String>? personalizedHeader,
  }) async {
    // 1. Faz a chamada HTTP
    final resultApi = await post(
      apiConfig,
      endpoint: endpoint,
      data: data,
      isMultipart: isMultipart,
      personalizedHeader: personalizedHeader,
    );

    // 2. Extrai o corpo usando seu novo método que limpa 'null' e vazios
    final String? content = resultApi.bodyAsString;

    // 3. Se não for sucesso, o método post() já deveria ter lançado erro,
    // mas garantimos o retorno aqui caso o fluxo continue.
    if (!resultApi.isSuccess) {
      return ResultModel<M>(result: resultApi);
    }

    debugPrint("Log: API Success detected.");

    // 4. Se o corpo for nulo/vazio (ex: 204 No Content), retornamos sucesso SEM parse
    if (content == null) {
      debugPrint("Log: Empty body (null). Returning without Isolate parse.");
      return ResultModel<M>(result: resultApi);
    }

    // 5. Se tem conteúdo, entramos no Try/Catch apenas para o processamento do Isolate
    try {
      debugPrint("Log: Starting Isolate decode with content.");
      final model = await compute(
        decodeJsonInIsolate<M>,
        [content, parser],
      );

      return ResultModel<M>(model: model, result: resultApi);
    } catch (e, s) {
      debugPrint('Log Error: Failed to decode JSON: $e');
      debugPrintStack(stackTrace: s);
      rethrow;
    }
  }

  // Crie um método específico para listas para evitar a confusão do 'asList'
  Future<List<M>> postList<M>(
    T apiConfig,
    String endpoint,
    M Function(Map<String, dynamic>) parser, {
    dynamic data,
    bool isMultipart = false,
    Map<String, String>? personalizedHeader,
  }) async {
    final resultApi = await post(
      apiConfig,
      endpoint: endpoint,
      data: data,
      isMultipart: isMultipart,
      personalizedHeader: personalizedHeader,
    );

    try {
      return await compute(decodeJsonListInIsolate<M>, [
        resultApi.bodyAsString,
        parser,
      ]);
    } catch (e, s) {
      debugPrint('Erro ao decodificar Lista JSON no POST: $e');
      debugPrintStack(stackTrace: s);
      rethrow;
    }
  }
}
