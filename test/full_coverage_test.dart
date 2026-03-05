import 'dart:convert';
import 'package:volt_net/volt_net.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:async';

class MockHttpClient extends Mock implements Client {}

class FakeBaseRequest extends Fake implements BaseRequest {}

class _FullApiConfig extends BaseApiUrlConfig {
  @override
  String resolveBaseUrl() => 'https://api.full.com';
  @override
  Future<Map<String, String>> getHeader() async =>
      {'Content-Type': 'application/json'};
  @override
  Future<String> getToken() async => 'full_token';
}

class TestInterceptor extends VoltInterceptor {
  bool reqCalled = false;
  bool resCalled = false;

  @override
  FutureOr<BaseRequest> onRequest(BaseRequest request) async {
    reqCalled = true;
    return request;
  }

  @override
  FutureOr<Response> onResponse(Response response) async {
    resCalled = true;
    return response;
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late MockHttpClient mockClient;
  late _FullApiConfig apiConfig;

  setUpAll(() {
    registerFallbackValue(FakeBaseRequest());
    registerFallbackValue(Uri.parse('https://api.full.com'));
  });

  setUp(() async {
    mockClient = MockHttpClient();
    apiConfig = _FullApiConfig();
    SqlDatabaseHelper.databaseName = ':memory:';
    await SqlDatabaseHelper.reset();
    Volt.clearInterceptors();
  });

  group('PUT & DELETE Coverage', () {
    test('PUT request success', () async {
      final putRequest = PutRequest(client: mockClient);
      when(() => mockClient.send(any()))
          .thenAnswer((_) async => StreamedResponse(
                Stream.fromIterable([utf8.encode('{"updated":true}')]),
                200,
              ));

      final res =
          await putRequest.put(apiConfig, endpoint: '/update', data: {'id': 1});
      expect(res.isSuccess, true);
      expect(res.jsonBody['updated'], true);
    });

    test('DELETE request success', () async {
      final deleteRequest = DeleteRequest(client: mockClient);
      when(() => mockClient.send(any()))
          .thenAnswer((_) async => StreamedResponse(
                Stream.fromIterable([utf8.encode('{"deleted":true}')]),
                200,
              ));

      final res = await deleteRequest.delete(apiConfig, endpoint: '/item/1');
      expect(res.isSuccess, true);
      expect(res.jsonBody['deleted'], true);
    });

    test('PUT offline sync enqueuing', () async {
      final putRequest = PutRequest(client: mockClient);
      when(() => mockClient.send(any()))
          .thenThrow(HttpNetworkException('No internet'));

      final res = await putRequest
          .put(apiConfig, endpoint: '/sync-put', data: {'val': 10});
      expect(res.isPending, true);

      final db = await SqlDatabaseHelper().database;
      final pending = await db.query(SqlDatabaseHelper.syncTable);
      expect(pending.any((row) => row['method'] == 'PUT'), true);
    });

    test('DELETE offline sync enqueuing', () async {
      final deleteRequest = DeleteRequest(client: mockClient);
      when(() => mockClient.send(any()))
          .thenThrow(HttpNetworkException('No internet'));

      final res = await deleteRequest.delete(apiConfig, endpoint: '/sync-del');
      expect(res.isPending, true);

      final db = await SqlDatabaseHelper().database;
      final pending = await db.query(SqlDatabaseHelper.syncTable);
      expect(pending.any((row) => row['method'] == 'DELETE'), true);
    });
  });

  group('ResultApi & ResultModel Extra Coverage', () {
    test('ResultApi jsonBody returns null on invalid JSON', () {
      final res = ResultApi(response: Response('not a json', 200));
      expect(res.jsonBody, isNull);
    });

    test('ResultModel should store error correctly', () {
      final error = VoltNetException('Fail');
      final model = ResultModel<String>(error: error);
      expect(model.error, error);
      expect(model.hasError, true);
    });
  });

  group('VoltInterceptors Coverage', () {
    test('Interceptors should be called', () async {
      final getRequest = GetRequest(client: mockClient);
      final interceptor = TestInterceptor();

      Volt.addInterceptor(interceptor);

      when(() => mockClient.send(any()))
          .thenAnswer((_) async => StreamedResponse(
                Stream.fromIterable([utf8.encode('{}')]),
                200,
              ));

      await getRequest.get(apiConfig, '/intercept');

      expect(interceptor.reqCalled, true);
      expect(interceptor.resCalled, true);

      Volt.removeInterceptor(interceptor);
    });
  });
}
