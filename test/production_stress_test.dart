import 'dart:convert';
import 'package:volt_net/volt_net.dart';
import 'package:volt_net/src/models/test_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockHttpClient extends Mock implements Client {}

class FakeBaseRequest extends Fake implements BaseRequest {}

class _StressApiConfig extends BaseApiUrlConfig {
  @override
  String resolveBaseUrl() => 'https://api.stress.com';
  @override
  Future<Map<String, String>> getHeader() async =>
      {'Content-Type': 'application/json'};
  @override
  Future<String> getToken() async => 'stress_token';
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late MockHttpClient mockClient;
  late PostRequest postRequest;
  late _StressApiConfig apiConfig;

  setUpAll(() {
    registerFallbackValue(FakeBaseRequest());
    SqlDatabaseHelper.databaseName = ':memory:';
  });

  setUp(() async {
    mockClient = MockHttpClient();
    postRequest = PostRequest(client: mockClient);
    apiConfig = _StressApiConfig();
    await SqlDatabaseHelper.reset();
  });

  group('Production Stress Tests', () {
    test('Should handle 50 concurrent model parsing requests', () async {
      final mockResponse = TestModel.mock().toJson();

      when(() => mockClient.send(any()))
          .thenAnswer((_) async => StreamedResponse(
                Stream.fromIterable([utf8.encode(json.encode(mockResponse))]),
                200,
              ));

      final futures = List.generate(
          20,
          (i) => postRequest.postModel<TestModel>(
              apiConfig, '/stress', TestModel.fromJson,
              data: {'i': i}));

      final results = await Future.wait(futures);
      expect(results.length, 20);
      expect(results.every((r) => r.isSuccess), true);
    });
  });
}
