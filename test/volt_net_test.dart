import 'package:flutter_test/flutter_test.dart';
import 'package:volt_net/volt_net.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    // Initialize database for test environment (PC)
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('VoltNet initialization smoke test', () async {
    // Should initialize without crashing
    await Volt.initialize(
      databaseName: 'test_volt.db',
      maxMemoryItems: 100,
      enableSync:
          false, // Disable sync to avoid background connectivity checks during test
    );
  });
}
