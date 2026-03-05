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

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late MockHttpClient mockClient;
  late _TestApiConfig apiConfig;
  late GetRequest getRequest;

  setUpAll(() {
    registerFallbackValue(FakeBaseRequest());
  });

  setUp(() async {
    mockClient = MockHttpClient();
    apiConfig = _TestApiConfig();
    SqlDatabaseHelper.databaseName = ':memory:';
    await SqlDatabaseHelper.reset();
    getRequest = GetRequest(client: mockClient);
    await CacheManager.init();
    Volt.timeout = const Duration(seconds: 1);
  });

  group('GetRequest Ultra-Coverage (Goal 92%+)', () {
    test('Sanitize complex query parameters (Iterable support)', () async {
      when(() => mockClient.send(any())).thenAnswer((_) async =>
          http.StreamedResponse(
              Stream.fromIterable([utf8.encode('{"ok":true}')]), 200));

      final params = {
        'tags': ['dart', 'flutter'],
        'id': 123,
      };

      final res =
          await getRequest.get(apiConfig, '/test', queryParameters: params);
      expect(res.isSuccess, true);
    });

    test('Network error fallback to EXPIRED cache', () async {
      final cacheManager = CacheManager();
      final resInitial =
          ResultApi(response: http.Response('{"cached":true}', 200));
      final fullUrl =
          Uri.parse(apiConfig.resolveBaseUrl()).resolve('/fallback').toString();

      await cacheManager.save(
        type: CacheType.disk,
        token: 'test_token',
        endpoint: fullUrl,
        data: resInitial,
      );

      when(() => mockClient.send(any()))
          .thenThrow(SocketException('No Internet'));

      final res = await getRequest.get(
        apiConfig,
        '/fallback',
        cacheEnabled: true,
        type: CacheType.disk,
        readCache: false,
      );

      expect(res.isSuccess, true);
      expect(res.jsonBody['cached'], true);
    });

    test('getWithDebounce mechanism', () async {
      int callCount = 0;
      when(() => mockClient.send(any())).thenAnswer((_) async {
        callCount++;
        return http.StreamedResponse(
            Stream.fromIterable([utf8.encode('{"count":$callCount}')]), 200);
      });

      final f1 = getRequest.getWithDebounce(apiConfig, '/db',
          delay: const Duration(milliseconds: 50));
      final f2 = getRequest.getWithDebounce(apiConfig, '/db',
          delay: const Duration(milliseconds: 50));

      final results = await Future.wait([f1, f2]);

      expect(results[0].isCancelled, true);
      expect(results[1].isSuccess, true);
      expect(callCount, 1);
    });

    test('getModelResult and getListResult isolates coverage', () async {
      when(() => mockClient.send(any())).thenAnswer((_) async =>
          http.StreamedResponse(
              Stream.fromIterable([utf8.encode('{"name":"Volt"}')]), 200));

      final res = await getRequest.getModelResult<String>(
          apiConfig, '/m', (m) => m['name']);
      expect(res.model, 'Volt');

      when(() => mockClient.send(any())).thenAnswer((_) async =>
          http.StreamedResponse(
              Stream.fromIterable([utf8.encode('[{"name":"V1"}]')]), 200));

      final resList = await getRequest.getListResult<String>(
          apiConfig, '/l', (m) => m['name']);
      expect(resList.model!.first, 'V1');
    });

    test('Timeout handling (completes with ResultApi null response)', () async {
      when(() => mockClient.send(any())).thenAnswer((_) async {
        await Future.delayed(const Duration(seconds: 2));
        return http.StreamedResponse(Stream.fromIterable([]), 200);
      });

      final res = await getRequest.get(apiConfig, '/to');
      expect(res.response, isNull);
      expect(res.isNetworkError, true);
    });

    test('Generic Exception should throw (completeError branch)', () async {
      when(() => mockClient.send(any())).thenThrow(Exception('Generic Error'));

      expect(() => getRequest.get(apiConfig, '/error'),
          throwsA(isA<VoltNetException>()));
    });

    test('getBytes with cache hit', () async {
      final cacheManager = CacheManager();
      final resInitial = ResultApi(response: http.Response('hello', 200));
      await cacheManager.save(
          type: CacheType.disk,
          token: 'test_token',
          endpoint: 'https://test.com/file',
          data: resInitial);

      final bytes = await getRequest
          .getBytes(apiConfig, 'https://test.com/file', cacheEnabled: true);
      expect(utf8.decode(bytes), 'hello');
    });
  });
}
