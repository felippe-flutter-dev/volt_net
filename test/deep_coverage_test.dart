import 'package:volt_net/volt_net.dart';
import 'package:volt_net/src/models/test_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockSqlModel extends SqlModel {
  @override
  String get tableName => 'deep_test_table';
  @override
  Map<String, String> get tableSchema =>
      {'id': 'INTEGER PRIMARY KEY', 'val': 'TEXT'};
  @override
  Map<String, dynamic> toSqlMap() => {'id': 1, 'val': 'test'};
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() async {
    SqlDatabaseHelper.databaseName = ':memory:';
    await SqlDatabaseHelper.reset();
  });

  group('SqlDatabaseHelper Deep Coverage', () {
    test('Should handle database initialization concurrency', () async {
      final helper = SqlDatabaseHelper();
      final results = await Future.wait([
        helper.database,
        helper.database,
        helper.database,
      ]);
      expect(results[0], results[1]);
      expect(results[1], results[2]);
    });

    test('getModels should return empty list on non-existent table', () async {
      final helper = SqlDatabaseHelper();
      final results = await helper.getModels('table_that_does_not_exist');
      expect(results, isEmpty);
    });

    test('clearVolatileCache should only remove volatile items', () async {
      final helper = SqlDatabaseHelper();
      await helper.saveCache(
          key: 'v', body: 'b', statusCode: 200, isVolatile: true);
      await helper.saveCache(
          key: 'p', body: 'b', statusCode: 200, isVolatile: false);

      await helper.clearVolatileCache();

      expect(await helper.getCache('v'), isNull);
      expect(await helper.getCache('p'), isNotNull);
    });
  });

  group('CacheManager Logic Coverage', () {
    test('manageMemoryGrowth should remove oldest items when limit is reached',
        () async {
      CacheManager.maxMemoryItems = 2;
      final cache = CacheManager();
      final res = ResultApi(response: Response('{}', 200));

      await cache.save(
          type: CacheType.memory, token: 't', endpoint: '1', data: res);
      await cache.save(
          type: CacheType.memory, token: 't', endpoint: '2', data: res);
      await cache.save(
          type: CacheType.memory, token: 't', endpoint: '3', data: res);

      final c1 =
          await cache.get(type: CacheType.memory, token: 't', endpoint: '1');
      final c2 =
          await cache.get(type: CacheType.memory, token: 't', endpoint: '2');
      final c3 =
          await cache.get(type: CacheType.memory, token: 't', endpoint: '3');

      expect(c1, isNull);
      expect(c2, isNotNull);
      expect(c3, isNotNull);
    });

    test('get should promote from L2 to L1 if not in L1', () async {
      final cache = CacheManager();
      final res = ResultApi(response: Response('{"l2":true}', 200));

      await cache.save(
          type: CacheType.disk, token: 't', endpoint: 'l2_test', data: res);

      final cached = await cache.get(
          type: CacheType.both, token: 't', endpoint: 'l2_test');
      expect(cached?.bodyAsString, contains('l2'));

      final l1Cached = await cache.get(
          type: CacheType.memory, token: 't', endpoint: 'l2_test');
      expect(l1Cached, isNotNull);
    });

    test('get with expired TTL should return null', () async {
      final cache = CacheManager();
      final res = ResultApi(response: Response('{}', 200));

      await cache.save(
          type: CacheType.disk, token: 't', endpoint: 'ttl_test', data: res);

      await Future.delayed(Duration(milliseconds: 10));

      final cached = await cache.get(
          type: CacheType.disk,
          token: 't',
          endpoint: 'ttl_test',
          ttl: Duration(milliseconds: 1));
      expect(cached, isNull);
    });
  });

  group('Volt Core Coverage', () {
    test('Volt.initialize should apply all settings', () async {
      await Volt.initialize(
        databaseName: 'custom_volt.db',
        maxMemoryItems: 42,
        enableSync: false,
      );
      expect(SqlDatabaseHelper.databaseName, 'custom_volt.db');
      expect(CacheManager.maxMemoryItems, 42);
    });
  });

  group('Models Coverage', () {
    test('TestModel toString coverage', () {
      final model = TestModel(nome: 'Flutter Test');
      expect(model.toString(), 'TestModel(nome: Flutter Test)');
    });
  });
}
