import 'dart:convert';
import 'package:volt_net/volt_net.dart';
import 'package:volt_net/src/models/test_model.dart';
import 'package:volt_net/src/repositories/teste_repo.dart';
import 'package:flutter/cupertino.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

class MockHttpClient extends Mock implements http.Client {}

class FakeUri extends Fake implements Uri {}

void main() {
  late TesteRepo testeRepo;
  late MockHttpClient mockClient;
  late GetRequest getRequest;
  late CacheManager cacheManager;
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    registerFallbackValue(FakeUri());
    // No ambiente de teste, o sqflite precisa de inicialização especial ou mock
    // Para este teste unitário, vamos focar no comportamento do CacheManager
    await CacheManager.init();
    cacheManager = CacheManager();
    mockClient = MockHttpClient();
    getRequest = GetRequest(client: mockClient, cache: cacheManager);
    testeRepo = TesteRepo(getRequest);
  });

  group('Testando GET', () {
    test('Deve retornar o objeto Teste', () async {
      final jsonResponse = jsonEncode(TestModel.mock());
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => http.Response(jsonResponse, 200));

      final result = await testeRepo.getTestModel();

      expect(result.nome, 'Flutter Test', reason: 'Retornado: ${result.nome}');

      verify(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).called(1);
    });

    test(
      'Deve retornar uma lista do objeto Teste',
      () async {
        final jsonResponse = jsonEncode(TestModel.mockList());
        when(
          () => mockClient.get(any(), headers: any(named: 'headers')),
        ).thenAnswer(
          (_) async => http.Response(jsonResponse, 200),
        );

        final result = await testeRepo.getTestModelList();

        debugPrint("teste: ${result[0].toJson()}");

        expect(result[0].nome, 'Item 1',
            reason: 'Retornado no objeto 1: ${result[0].nome}');
        expect(result[1].nome, 'Item 2');

        verify(() => mockClient.get(any(), headers: any(named: 'headers')))
            .called(1);
      },
    );
  });
}
