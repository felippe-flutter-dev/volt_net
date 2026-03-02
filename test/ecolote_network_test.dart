import 'dart:convert';
import 'package:volt_net/volt_net.dart';
import 'package:volt_net/src/models/test_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockHttpClient extends Mock implements http.Client {}

class FakeUri extends Fake implements Uri {}

class MockSqlModel extends SqlModel {
  @override
  String get tableName => 'mock_table';
  @override
  Map<String, String> get tableSchema =>
      {'id': 'INTEGER PRIMARY KEY', 'name': 'TEXT'};
  @override
  Map<String, dynamic> toSqlMap() => {'id': 1, 'name': 'Test'};
}

class TestConfig extends BaseApiUrlConfig {
  @override
  String get baseUrl => 'https://api.test.com';
  @override
  Future<String> getToken() async => 'mock_token';
}

void main() {
  // Inicializa o banco de dados para ambiente de teste (PC)
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late MockHttpClient mockClient;
  late CacheManager cacheManager;
  late GetRequest getRequest;

  setUpAll(() async {
    registerFallbackValue(FakeUri());
    // Garante banco em memória e limpo para este arquivo de teste
    SqlDatabaseHelper.databaseName = ':memory:';
    await SqlDatabaseHelper.reset();
  });

  setUp(() async {
    mockClient = MockHttpClient();
    await CacheManager.init();
    await CacheManager.clearAll();
    cacheManager = CacheManager();
    getRequest = GetRequest(client: mockClient, cache: cacheManager);
  });

  group('ResultApi Tests', () {
    test('Should identify success status codes', () {
      final res = ResultApi(response: http.Response('{}', 200));
      expect(res.isSuccess, true);
      expect(res.isClientError, false);
    });

    test('Should identify error status codes', () {
      final res = ResultApi(response: http.Response('Error', 404));
      expect(res.isSuccess, false);
      expect(res.isClientError, true);
    });

    test('Should return body as string correctly', () {
      final res = ResultApi(body: {'key': 'value'});
      expect(res.bodyAsString, '{"key":"value"}');
    });
  });

  group('CacheManager & SQL Tests', () {
    test('Should save and retrieve from L1 (Memory)', () async {
      final result = ResultApi(response: http.Response('{"data":1}', 200));
      await cacheManager.save(
        type: CacheType.memory,
        token: 'token',
        endpoint: '/test',
        data: result,
      );

      final cached = await cacheManager.get(
        type: CacheType.memory,
        token: 'token',
        endpoint: '/test',
      );

      expect(cached?.bodyAsString, result.bodyAsString);
    });

    test('Should respect TTL (Time to Live)', () async {
      final result = ResultApi(response: http.Response('{"data":1}', 200));
      await cacheManager.save(
        type: CacheType.disk,
        token: 'token',
        endpoint: '/ttl_test',
        data: result,
      );

      // Aguarda 10ms e testa com TTL de 1ms (deve expirar)
      await Future.delayed(const Duration(milliseconds: 10));

      final cached = await cacheManager.get(
        type: CacheType.disk,
        token: 'token',
        endpoint: '/ttl_test',
        ttl: const Duration(milliseconds: 1),
      );

      expect(cached, null);
    });

    test('Should save dynamic SqlModel', () async {
      final model = MockSqlModel();
      await cacheManager.saveModel(model);

      final data = await cacheManager.getModels('mock_table');
      expect(data.length, 1);
      expect(data.first['name'], 'Test');
    });
  });

  group('GetRequest Integration Tests', () {
    test('Should perform HTTP GET and save cache', () async {
      final config = TestConfig();
      final responseBody = jsonEncode(TestModel.mock().toJson());

      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(responseBody, 200));

      final result = await getRequest.getModel<TestModel>(
        config,
        '/profile',
        TestModel.fromJson,
        cacheEnabled: true,
        type: CacheType.both,
      );

      expect(result.nome, 'Flutter Test');

      // Verifica se chamou o client
      verify(() => mockClient.get(any(), headers: any(named: 'headers')))
          .called(1);

      // Segunda chamada deve vir do cache (não deve chamar o client)
      await getRequest.getModel<TestModel>(
        config,
        '/profile',
        TestModel.fromJson,
        cacheEnabled: true,
        type: CacheType.both,
      );

      verifyNever(() => mockClient.get(any(), headers: any(named: 'headers')));
    });

    test('Should throw ApiException on 401 Unauthorized', () async {
      final config = TestConfig();
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer(
              (_) async => http.Response('{"error": "unauthorized"}', 401));

      expect(
        () => getRequest.get(config, '/private_data'),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('Should handle corrupted cache by falling back to network', () async {
      final config = TestConfig();
      final validResponse = jsonEncode(TestModel.mock().toJson());

      // 1. Inserir manualmente um cache malformado (JSON quebrado)
      await cacheManager.save(
        type: CacheType.disk,
        token: 'mock_token',
        endpoint: '/corrupted',
        data: ResultApi(response: http.Response('{"invalid_json: ', 200)),
      );

      // Mock da rede para o fallback
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(validResponse, 200));

      // Deve ignorar o cache quebrado e retornar o objeto da rede
      final result = await getRequest.getModel<TestModel>(
        config,
        '/corrupted',
        TestModel.fromJson,
        cacheEnabled: true,
        type: CacheType.disk,
      );

      expect(result.nome, 'Flutter Test');
      verify(() => mockClient.get(any(), headers: any(named: 'headers')))
          .called(1);
    });

    test('Should use personalizedHeader instead of default config headers',
        () async {
      final config = TestConfig();
      final customHeader = {'Custom-Key': 'Custom-Value'};
      final responseBody = jsonEncode(TestModel.mock().toJson());

      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(responseBody, 200));

      await getRequest.get(config, '/custom', personalizedHeader: customHeader);

      // Verifica se o client recebeu o header customizado, e NÃO o Bearer default
      verify(() => mockClient.get(
            any(),
            headers: customHeader,
          )).called(1);
    });
  });
}
