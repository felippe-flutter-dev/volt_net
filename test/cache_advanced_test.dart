import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:volt_net/volt_net.dart';
import 'package:http/http.dart' as http;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late CacheManager cacheManager;

  setUp(() async {
    SqlDatabaseHelper.databaseName = ':memory:';
    await SqlDatabaseHelper.reset();
    cacheManager = CacheManager();
    await CacheManager.init();
    CacheManager.clearMemory();
  });

  group('CacheManager & SqlDatabaseHelper Advanced Coverage', () {
    test('CacheManager TTL expiration in memory (L1)', () async {
      final res = ResultApi(response: http.Response('{"id":1}', 200));

      await cacheManager.save(
        type: CacheType.memory,
        token: 'user1',
        endpoint: '/test',
        data: res,
      );

      // Verify it is in memory
      var cached = await cacheManager.get(
        type: CacheType.memory,
        token: 'user1',
        endpoint: '/test',
        ttl: const Duration(seconds: 1),
      );
      expect(cached, isNotNull);

      // Wait for expiration
      await Future.delayed(const Duration(milliseconds: 1100));

      cached = await cacheManager.get(
        type: CacheType.memory,
        token: 'user1',
        endpoint: '/test',
        ttl: const Duration(seconds: 1),
      );
      expect(cached, isNull);
    });

    test('CacheManager TTL expiration on disk (L2)', () async {
      final res = ResultApi(response: http.Response('{"id":2}', 200));

      await cacheManager.save(
        type: CacheType.disk,
        token: 'user2',
        endpoint: '/disk-test',
        data: res,
      );

      CacheManager.clearMemory();

      // Wait for expiration
      await Future.delayed(const Duration(milliseconds: 50));

      var cached = await cacheManager.get(
        type: CacheType.disk,
        token: 'user2',
        endpoint: '/disk-test',
        ttl: const Duration(milliseconds: 10),
      );
      expect(cached, isNull);
    });

    test('CacheManager LRU (maxMemoryItems) coverage', () async {
      CacheManager.maxMemoryItems = 2;
      final res = ResultApi(response: http.Response('{}', 200));

      await cacheManager.save(
          type: CacheType.memory, token: 't', endpoint: '/1', data: res);
      await cacheManager.save(
          type: CacheType.memory, token: 't', endpoint: '/2', data: res);
      await cacheManager.save(
          type: CacheType.memory, token: 't', endpoint: '/3', data: res);

      // /1 should be evicted
      expect(
          await cacheManager.get(
              type: CacheType.memory, token: 't', endpoint: '/1'),
          isNull);
      expect(
          await cacheManager.get(
              type: CacheType.memory, token: 't', endpoint: '/2'),
          isNotNull);
      expect(
          await cacheManager.get(
              type: CacheType.memory, token: 't', endpoint: '/3'),
          isNotNull);
    });

    test('SqlDatabaseHelper migration and versioning', () async {
      // Testing migration logic implicitly via initialize
      await SqlDatabaseHelper().database;
      // Success means no crash in onCreate/onUpgrade
    });

    test('CacheManager clearAll wipe L1 and L2', () async {
      final res = ResultApi(response: http.Response('{}', 200));
      await cacheManager.save(
          type: CacheType.both, token: 't', endpoint: '/all', data: res);

      await CacheManager.clearAll();

      expect(
          await cacheManager.get(
              type: CacheType.both, token: 't', endpoint: '/all'),
          isNull);
    });
  });
}
