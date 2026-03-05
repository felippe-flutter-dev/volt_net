import 'dart:convert';
import 'package:http/http.dart';
import 'package:volt_net/volt_net.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockHttpClient extends Mock implements Client {}

class FakeBaseRequest extends Fake implements BaseRequest {}

class _TestApiConfig extends BaseApiUrlConfig {
  @override
  Future<String> getToken() async => 'test_token';
  @override
  Future<Map<String, String>> getHeader() async => {
        'Authorization': 'Bearer test_token',
        'Content-Type': 'application/json',
      };
  @override
  String resolveBaseUrl() => 'https://api.test.com';
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late MockHttpClient mockClient;
  late CacheManager cacheManager;
  late GetRequest getRequest;
  late PostRequest postRequest;
  late _TestApiConfig apiConfig;

  setUpAll(() async {
    registerFallbackValue(FakeBaseRequest());
    SqlDatabaseHelper.databaseName = ':memory:';
    apiConfig = _TestApiConfig();
  });

  setUp(() async {
    mockClient = MockHttpClient();
    await SqlDatabaseHelper.reset();
    await CacheManager.init();
    cacheManager = CacheManager();
    getRequest = GetRequest(client: mockClient, cache: cacheManager);
    postRequest = PostRequest(client: mockClient, cache: cacheManager);
  });

  group('ResultApi Model Tests', () {
    test('Should correctly identify HTTP status categories', () {
      final success = ResultApi(response: Response('{}', 200));
      final clientErr = ResultApi(response: Response('{}', 400));
      final serverErr = ResultApi(response: Response('{}', 500));

      expect(success.isSuccess, true);
      expect(clientErr.isClientError, true);
      expect(serverErr.isServerError, true);
    });
  });

  group('CacheManager & L1/L2 Integrity', () {
    test('Should persist data in L1 and then L2', () async {
      final data = ResultApi(response: Response('{"id": 1}', 200));
      const endpoint = 'https://api.test.com/data';
      const token = 'test_token';

      await cacheManager.save(
        type: CacheType.both,
        token: token,
        endpoint: endpoint,
        data: data,
      );

      final l1 = await cacheManager.get(
        type: CacheType.memory,
        token: token,
        endpoint: endpoint,
      );
      expect(l1?.bodyAsString, isNotNull);

      // Only clear memory to test L2 persistence
      CacheManager.clearMemory();

      final l2 = await cacheManager.get(
        type: CacheType.disk,
        token: token,
        endpoint: endpoint,
      );
      expect(l2?.bodyAsString, isNotNull);
    });
  });

  group('GetRequest & Resilience', () {
    test('Should fallback to cache on network failure', () async {
      const endpoint = 'resilient-data';
      final fullUrl = 'https://api.test.com/resilient-data';

      await cacheManager.save(
        type: CacheType.disk,
        token: 'test_token',
        endpoint: fullUrl,
        data: ResultApi(response: Response('{"cached": true}', 200)),
      );

      when(() => mockClient.send(any()))
          .thenThrow(ClientException('No internet'));

      final result = await getRequest.get(
        apiConfig,
        endpoint,
        cacheEnabled: true,
        type: CacheType.disk,
      );

      expect(result.jsonBody['cached'], true);
    });

    test('Should throw typed VoltNetException for 500 errors', () async {
      when(() => mockClient.send(any()))
          .thenAnswer((_) async => StreamedResponse(
                Stream.fromIterable([utf8.encode('Server Error')]),
                500,
              ));

      expect(
        () => getRequest.get(apiConfig, '/error'),
        throwsA(isA<HttpServerException>()
            .having((e) => e.statusCode, 'statusCode', 500)),
      );
    });
  });

  group('PostRequest & Resilient Batch', () {
    test('Should inject Idempotency-Key in batch requests', () async {
      when(() => mockClient.send(any()))
          .thenAnswer((_) async => StreamedResponse(
                Stream.fromIterable([utf8.encode('{"success": true}')]),
                201,
              ));

      await postRequest.resilientBatch(
        [
          ({extraHeaders}) => postRequest.post(apiConfig,
              endpoint: '/step1', extraHeaders: extraHeaders),
          ({extraHeaders}) => postRequest.post(apiConfig,
              endpoint: '/step2', extraHeaders: extraHeaders),
        ],
        idempotencyKey: 'batch-123',
      );

      verify(() => mockClient.send(any(
          that: isA<BaseRequest>().having((r) => r.headers['Idempotency-Key'],
              'Idempotency-Key', startsWith('batch-123'))))).called(2);
    });
  });
}
