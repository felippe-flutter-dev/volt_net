import 'dart:convert';
import 'package:volt_net/volt_net.dart';
import 'package:volt_net/src/models/test_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockHttpClient extends Mock implements Client {}

class FakeBaseRequest extends Fake implements BaseRequest {}

class _CoverageApiConfig extends BaseApiUrlConfig {
  @override
  String resolveBaseUrl() => 'https://api.test.com';
  @override
  Future<Map<String, String>> getHeader() async =>
      {'Content-Type': 'application/json'};
  @override
  Future<String> getToken() async => 'coverage_token';
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late MockHttpClient mockClient;
  late PostRequest postRequest;
  late _CoverageApiConfig apiConfig;

  setUpAll(() {
    registerFallbackValue(FakeBaseRequest());
    registerFallbackValue(Uri.parse('https://api.test.com'));
  });

  setUp(() async {
    mockClient = MockHttpClient();
    postRequest = PostRequest(client: mockClient);
    apiConfig = _CoverageApiConfig();
    SqlDatabaseHelper.databaseName = ':memory:';
    await SqlDatabaseHelper.reset();
  });

  group('VoltNet v2.0 Features Coverage', () {
    test('ResilientBatch with IdempotencyKey', () async {
      when(() => mockClient.send(any()))
          .thenAnswer((_) async => StreamedResponse(
                Stream.fromIterable([utf8.encode('{"ok":true}')]),
                200,
              ));

      final batchResult = await postRequest.resilientBatch(
        [
          ({extraHeaders}) => postRequest.post(apiConfig,
              endpoint: '/step1', extraHeaders: extraHeaders),
          ({extraHeaders}) => postRequest.post(apiConfig,
              endpoint: '/step2', extraHeaders: extraHeaders),
        ],
        idempotencyKey: 'batch-test',
      );

      expect(batchResult.length, 2);
      expect(batchResult.every((r) => r.isSuccess), true);
    });

    test('postModel using Isolates and cache fallback', () async {
      final mockData = TestModel.mock().toJson();
      when(() => mockClient.send(any()))
          .thenAnswer((_) async => StreamedResponse(
                Stream.fromIterable([utf8.encode(json.encode(mockData))]),
                200,
              ));

      final res = await postRequest.postModel<TestModel>(
        apiConfig,
        '/data',
        TestModel.fromJson,
      );

      expect(res.model?.nome, 'Flutter Test');
      expect(res.result?.isSuccess, true);
    });
  });
}
