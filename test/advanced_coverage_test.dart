import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:volt_net/volt_net.dart';

class MockHttpClient extends Mock implements http.Client {}

class FakeBaseRequest extends Fake implements http.BaseRequest {}

class _TestApiConfig extends BaseApiUrlConfig {
  @override
  String resolveBaseUrl() => 'https://api.test.com';
  @override
  Future<Map<String, String>> getHeader() async =>
      {'Authorization': 'Bearer test'};
  @override
  Future<String> getToken() async => 'test_token';
}

class DefaultInterceptor extends VoltInterceptor {}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late MockHttpClient mockClient;
  late _TestApiConfig apiConfig;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue(FakeBaseRequest());
    registerFallbackValue(Uri.parse('https://api.test.com'));
  });

  setUp(() async {
    mockClient = MockHttpClient();
    apiConfig = _TestApiConfig();
    SqlDatabaseHelper.databaseName = ':memory:';
    await SqlDatabaseHelper.reset();
    Volt.clearInterceptors();
    tempDir = await Directory.systemTemp.createTemp('volt_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('VoltInterceptor Default Implementation Coverage', () {
    test('Default implementations should return request/response as is',
        () async {
      final interceptor = DefaultInterceptor();
      final request = http.Request('GET', Uri.parse('https://api.test.com'));
      final response = http.Response('{}', 200);

      expect(await interceptor.onRequest(request), request);
      expect(await interceptor.onResponse(response), response);

      // onError should not throw
      expect(() => interceptor.onError(Exception('test')), returnsNormally);
    });
  });

  group('ResultModel Comprehensive Coverage', () {
    test('ResultModel getters logic', () {
      final resSuccess = ResultApi(response: http.Response('{}', 200));
      final modelSuccess =
          ResultModel<String>(model: 'data', result: resSuccess);
      expect(modelSuccess.isSuccess, true);
      expect(modelSuccess.hasError, false);
      expect(modelSuccess.errorMessage, 'Unknown error');

      final resError = ResultApi(response: http.Response('Error', 500));
      final modelError = ResultModel<String>(result: resError, error: 'Fail');
      expect(modelError.isSuccess, false);
      expect(modelError.hasError, true);
      expect(modelError.errorMessage, 'Fail');

      final modelCancelled =
          ResultModel<String>(result: ResultApi(isCancelled: true));
      expect(modelCancelled.isCancelled, true);

      final modelPending =
          ResultModel<String>(result: ResultApi(isPending: true));
      expect(modelPending.isPending, true);
    });
  });

  group('GetRequest & PostRequest Advanced Scenarios', () {
    test('GetRequest cancelPrevious should cancel active request', () async {
      final getRequest = GetRequest(client: mockClient);

      when(() => mockClient.send(any())).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 100));
        return http.StreamedResponse(
            Stream.fromIterable([utf8.encode('{}')]), 200);
      });

      final future1 = getRequest.get(apiConfig, '/slow', cancelPrevious: true);
      final future2 = getRequest.get(apiConfig, '/slow', cancelPrevious: true);

      final result1 = await future1;
      final result2 = await future2;

      expect(result1.isCancelled, true);
      expect(result2.isSuccess, true);
    });

    test('PostRequest with complex multipart data', () async {
      final postRequest = PostRequest(client: mockClient);

      // Criar arquivo temporário real
      final testFile = File('${tempDir.path}/test.txt');
      await testFile.writeAsString('hello world');

      final file = VoltFile(path: testFile.path, field: 'file_field');

      when(() => mockClient.send(any())).thenAnswer((_) async =>
          http.StreamedResponse(
              Stream.fromIterable([utf8.encode('{"ok":true}')]), 200));

      final data = {
        'field': 'value',
        'single_file': file,
        'list_files': [file, file],
        'http_file': http.MultipartFile.fromBytes('raw', [1, 2, 3])
      };

      final res = await postRequest.post(apiConfig,
          endpoint: '/upload', data: data, isMultipart: true);
      expect(res.isSuccess, true);
    });

    test('PostRequest resilientBatch failure and rollback', () async {
      final postRequest = PostRequest(client: mockClient);
      bool rollbackCalled = false;

      final requests = [
        ({Map<String, String>? extraHeaders}) async =>
            ResultApi(response: http.Response('{}', 200)),
        ({Map<String, String>? extraHeaders}) async =>
            ResultApi(response: http.Response('Error', 400)),
      ];

      // Usar await expectLater para garantir que o fluxo assíncrono complete
      await expectLater(
          postRequest.resilientBatch(requests, onRollback: (results) async {
            rollbackCalled = true;
          }),
          throwsA(isA<VoltNetException>()));

      expect(rollbackCalled, true);
    });
  });

  group('Exception Mapping Coverage', () {
    test('ThrowHttpException maps various native exceptions', () {
      expect(
          ThrowHttpException.mapNativeException(const SocketException('test')),
          isA<HttpNetworkException>());
      expect(ThrowHttpException.mapNativeException(TimeoutException('test')),
          isA<HttpNetworkException>());
      expect(ThrowHttpException.mapNativeException(Exception('generic')),
          isA<VoltNetException>());
    });
  });

  group('GetRequest getBytes Error Handling', () {
    test('getBytes handles errors correctly', () async {
      final getRequest = GetRequest(client: mockClient);
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenThrow(const SocketException('No net'));

      expect(() => getRequest.getBytes(apiConfig, 'https://test.com/file'),
          throwsA(isA<HttpNetworkException>()));
    });

    test('getBytes returns non-success result as error', () async {
      final getRequest = GetRequest(client: mockClient);
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('Not Found', 404));

      expect(() => getRequest.getBytes(apiConfig, 'https://test.com/file'),
          throwsA(isA<HttpClientException>()));
    });
  });
}
