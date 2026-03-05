import 'package:flutter_test/flutter_test.dart';
import 'package:volt_net/volt_net.dart';
import 'package:volt_net/src/models/test_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestInterceptor extends VoltInterceptor {}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('DebugUtils & Volt Coverage Booster', () {
    test('DebugUtils full branch coverage', () {
      // Test with all combinations to hit every 'if' and 'forEach'
      DebugUtils.printUrl(
          method: 'POST',
          url: 'https://a.com',
          headers: {'a': 'b'},
          body: '{"x":1}');
      DebugUtils.printUrl(
          method: 'GET', url: 'https://a.com', headers: {}, body: '');

      DebugUtils.printCurl(
          method: 'PUT',
          url: 'https://b.com',
          headers: {'k': 'v'},
          body: '{"id":2}');
      final curl = DebugUtils.generateCurl(
          method: 'DELETE',
          url: 'https://c.com',
          body: '{"msg": "escaped "quote""}');
      expect(curl, contains('\\"quote\\"'));
    });

    test('Volt initialization variations', () async {
      SqlDatabaseHelper.databaseName = ':memory:';
      await SqlDatabaseHelper.reset();

      // Initialize with sync disabled to hit that branch
      await Volt.initialize(
        enableSync: false,
        maxMemoryItems: 50,
        defaultTimeout: const Duration(seconds: 10),
      );

      expect(CacheManager.maxMemoryItems, 50);
      expect(Volt.timeout.inSeconds, 10);

      // Test interceptor management
      final interceptor = TestInterceptor();
      Volt.addInterceptor(interceptor);
      expect(Volt.interceptors.contains(interceptor), true);
      Volt.removeInterceptor(interceptor);
      expect(Volt.interceptors.contains(interceptor), false);
    });
  });

  group('ResultApi & ResultModel Gaps', () {
    test('ResultApi with direct body map', () {
      final res = ResultApi(body: {'direct': true});
      expect(res.bodyAsString, contains('"direct":true'));
      expect(res.jsonBody['direct'], true);
      expect(res.isNetworkError, false);
    });

    test('ResultApi network error detection', () {
      final res = ResultApi(response: null, body: null, isCancelled: false);
      expect(res.isNetworkError, true);
    });

    test('ResultModel error messaging', () {
      final model = ResultModel<String>(error: 'Error String');
      expect(model.errorMessage, 'Error String');

      final modelNull = ResultModel<String>();
      expect(modelNull.errorMessage, 'Unknown error');
    });
  });

  group('TestModel & Edge Cases', () {
    test('TestModel methods', () {
      final model = TestModel.mock();
      expect(model.nome, 'Flutter Test');
      expect(model.toJson(), isA<Map>());
      expect(model.toString(), contains('TestModel'));

      final list = TestModel.mockList();
      expect(list.length, 2);

      final fromJsonNull = TestModel.fromJson({});
      expect(fromJsonNull.nome, 'Unknown');
    });

    test('CacheManager init with custom helper', () async {
      final customHelper = SqlDatabaseHelper();
      await CacheManager.init(dbHelper: customHelper);
      // Verify no crash
    });
  });
}
