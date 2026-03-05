import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:volt_net/src/utils/debouncer.dart';
import 'package:volt_net/src/utils/decode_json_isolate.dart';
import 'package:volt_net/volt_net.dart';
import 'package:flutter/material.dart';
import 'package:mocktail/mocktail.dart';

class MockSyncQueueManager extends Mock implements SyncQueueManager {}

void main() {
  setUp(() {
    SyncQueueManager.setMock(null);
  });

  group('DebugUtils Coverage', () {
    test('generateCurl should format simple GET correctly', () {
      final curl =
          DebugUtils.generateCurl(method: 'GET', url: 'https://test.com');
      expect(curl, contains('curl -X GET "https://test.com"'));
    });

    test('generateCurl should include headers and body', () {
      final curl = DebugUtils.generateCurl(
        method: 'POST',
        url: 'https://test.com',
        headers: {'Content-Type': 'application/json'},
        body: '{"id":1}',
      );
      expect(curl, contains('-H "Content-Type: application/json"'));
      expect(curl, contains('-d "{\\"id\\":1}"'));
    });

    test('printUrl and printCurl should not crash', () {
      DebugUtils.printUrl(method: 'GET', url: 'https://test.com');
      DebugUtils.printCurl(method: 'POST', url: 'https://test.com', body: '{}');
    });
  });

  group('Debouncer Coverage', () {
    test('run should delay execution', () async {
      int count = 0;
      final debouncer = Debouncer(delay: const Duration(milliseconds: 10));
      debouncer.run(() => count++);
      expect(count, 0);
      await Future.delayed(const Duration(milliseconds: 30));
      expect(count, 1);
    });

    test('run should cancel previous execution', () async {
      int count = 0;
      final debouncer = Debouncer(delay: const Duration(milliseconds: 20));
      debouncer.run(() => count++);
      debouncer.run(() => count++);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(count, 1);
    });

    test('cancel should stop execution', () async {
      int count = 0;
      final debouncer = Debouncer(delay: const Duration(milliseconds: 20));
      debouncer.run(() => count++);
      debouncer.cancel();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(count, 0);
    });
  });

  group('VoltLog Coverage', () {
    test('VoltLog methods should not crash', () {
      VoltLog.d('Debug');
      VoltLog.i('Info');
      VoltLog.w('Warning');
      VoltLog.e('Error', 'detail', StackTrace.current);
    });
  });

  group('Isolate Utils Coverage', () {
    test('decodeJsonInIsolate should decode simple map', () {
      const source = '{"name":"Test"}';
      final result = decodeJsonInIsolate<Map<String, dynamic>>(
          [source, (json) => json as Map<String, dynamic>]);
      expect(result['name'], 'Test');
    });

    test('decodeJsonListInIsolate should decode list', () {
      const source = '[{"id":1}, {"id":2}]';
      final result = decodeJsonListInIsolate<Map<String, dynamic>>(
          [source, (dynamic json) => json as Map<String, dynamic>]);
      expect(result.length, 2);
      expect(result[0]['id'], 1);
    });
  });

  group('VoltSyncListener Coverage', () {
    testWidgets('VoltSyncListener should render and trigger onSync',
        (tester) async {
      final mockSyncManager = MockSyncQueueManager();
      final controller = StreamController<void>.broadcast();

      when(() => mockSyncManager.onQueueFinished)
          .thenAnswer((_) => controller.stream);

      // Inject mock to avoid real timers and DB access
      SyncQueueManager.setMock(mockSyncManager);

      bool synced = false;

      await tester.pumpWidget(MaterialApp(
        home: VoltSyncListener(
          onSync: () => synced = true,
          child: const Text('Child'),
        ),
      ));

      expect(find.text('Child'), findsOneWidget);

      // Trigger event via mock stream
      controller.add(null);
      await tester.pump();

      expect(synced, true);

      await controller.close();
      SyncQueueManager.setMock(null);
    });
  });
}
