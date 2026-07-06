import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/data/todo_models.dart';
import 'package:mytodo/src/data/todo_store.dart';
import 'package:mytodo/src/sync/supabase_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'syncs local and remote event logs through Supabase REST shape',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await TodoStore.openInMemoryForTesting(
        device: const LocalDevice(
          deviceId: 'device-a',
          name: 'Device A',
          token: 'token-a',
        ),
      );
      await store.createTodo('Local task');

      const remoteEvent = TodoEvent(
        eventId: 'remote-event-1',
        deviceId: 'device-b',
        seq: 1,
        timestamp: 2000,
        type: 'todo.upsert',
        todoId: 'remote-todo-1',
        payload: {
          'id': 'remote-todo-1',
          'title': 'Remote task',
          'completed': false,
          'deleted': false,
          'createdAt': 2000,
          'updatedAt': 2000,
        },
      );
      final pushedRows = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      late final StreamSubscription<HttpRequest> subscription;
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });

      subscription = server.listen((request) async {
        expect(request.headers.value('apikey'), 'publishable');
        expect(request.uri.path, '/rest/v1/mytodo_events');
        request.response.headers.contentType = ContentType.json;

        if (request.method == 'GET') {
          request.response.write(
            jsonEncode([
              {
                'event_id': remoteEvent.eventId,
                'device_id': remoteEvent.deviceId,
                'seq': remoteEvent.seq,
                'timestamp': remoteEvent.timestamp,
                'type': remoteEvent.type,
                'todo_id': remoteEvent.todoId,
                'payload_json': remoteEvent.payload,
              },
            ]),
          );
          await request.response.close();
          return;
        }

        if (request.method == 'POST') {
          final text = await utf8.decoder.bind(request).join();
          pushedRows.addAll(
            (jsonDecode(text) as List).map(
              (row) => Map<String, Object?>.from(row as Map),
            ),
          );
          request.response.statusCode = HttpStatus.created;
          request.response.write('[]');
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final service = SupabaseSyncService(store);
      addTearDown(service.close);
      await service.saveConfig(
        SupabaseSyncConfig(
          enabled: true,
          autoSync: false,
          restUrl: 'http://127.0.0.1:${server.port}/rest/v1',
          publishableKey: 'publishable',
          tableName: 'mytodo_events',
          syncSpace: 'test-space',
        ),
      );

      final result = await service.syncNow();

      expect(result.pulled, 1);
      expect(result.pushed, greaterThanOrEqualTo(1));
      expect(store.todos.map((todo) => todo.title), contains('Remote task'));
      expect(pushedRows, isNotEmpty);
      expect(pushedRows.first['sync_space'], 'test-space');
      expect(pushedRows.first, containsPair('event_id', isNotEmpty));
    },
  );

  test('rejects secret keys in client configuration', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(
        deviceId: 'device-a',
        name: 'Device A',
        token: 'token-a',
      ),
    );
    final service = SupabaseSyncService(store);
    addTearDown(service.close);
    await service.saveConfig(
      const SupabaseSyncConfig(
        enabled: true,
        autoSync: false,
        restUrl: 'https://example.supabase.co/rest/v1',
        publishableKey: 'sb_secret_do_not_use',
        tableName: 'mytodo_events',
        syncSpace: 'test-space',
      ),
    );

    expect(service.syncNow(), throwsA(isA<FormatException>()));
  });

  test('persists remote sync configuration across service instances', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(
        deviceId: 'device-a',
        name: 'Device A',
        token: 'token-a',
      ),
    );
    final first = SupabaseSyncService(store);
    addTearDown(first.close);

    await first.saveConfig(
      const SupabaseSyncConfig(
        enabled: true,
        autoSync: true,
        restUrl: 'https://example.supabase.co/rest/v1',
        publishableKey: 'sb_publishable_local',
        tableName: 'mytodo_events',
        syncSpace: 'phone',
      ),
    );

    final second = SupabaseSyncService(store);
    addTearDown(second.close);
    await second.load();

    expect(second.config.enabled, isTrue);
    expect(second.config.autoSync, isTrue);
    expect(second.config.restUrl, 'https://example.supabase.co/rest/v1');
    expect(second.config.publishableKey, 'sb_publishable_local');
    expect(second.config.tableName, 'mytodo_events');
    expect(second.config.syncSpace, 'phone');
  });

  test('default configuration contains no project URL or key', () {
    final config = SupabaseSyncConfig.defaults();

    expect(config.restUrl, isEmpty);
    expect(config.publishableKey, isEmpty);
    expect(config.enabled, isFalse);
    expect(config.autoSync, isTrue);
  });
}
