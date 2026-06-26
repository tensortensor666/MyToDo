import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mytodo/src/data/todo_models.dart';
import 'package:mytodo/src/data/todo_store.dart';
import 'package:mytodo/src/sync/sync_service.dart';

void main() {
  test(
    'two local sync services pair and exchange todo events over HTTP',
    () async {
      final firstStore = await TodoStore.openInMemoryForTesting(
        device: const LocalDevice(
          deviceId: 'device-a',
          name: 'Device A',
          token: 'token-a',
        ),
      );
      final secondStore = await TodoStore.openInMemoryForTesting(
        device: const LocalDevice(
          deviceId: 'device-b',
          name: 'Device B',
          token: 'token-b',
        ),
      );
      final firstSync = SyncService(firstStore, enableMdns: false);
      final secondSync = SyncService(secondStore, enableMdns: false);

      await firstSync.start();
      await secondSync.start();
      addTearDown(firstSync.stop);
      addTearDown(secondSync.stop);

      await firstSync.pairWith(
        baseUrl: secondSync.localBaseUrl!,
        token: secondStore.device.token,
      );

      await firstStore.createTodo('From first');
      await secondStore.createTodo('From second');

      await firstSync.syncAllTrustedDevices();
      await secondSync.syncAllTrustedDevices();

      expect(
        firstStore.todos.map((todo) => todo.title),
        containsAll(<String>['From first', 'From second']),
      );
      expect(
        secondStore.todos.map((todo) => todo.title),
        containsAll(<String>['From first', 'From second']),
      );
    },
  );

  test('pairing keeps the reachable URL used by the caller', () async {
    final store = await TodoStore.openInMemoryForTesting(
      device: const LocalDevice(
        deviceId: 'device-a',
        name: 'Device A',
        token: 'token-a',
      ),
    );
    final sync = SyncService(store, enableMdns: false);
    await sync.start();
    addTearDown(sync.stop);
    await store.createTodo('Local before pairing');

    final pushedTitles = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late final StreamSubscription<HttpRequest> subscription;
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    Future<Map<String, Object?>> readJson(HttpRequest request) async {
      final text = await utf8.decoder.bind(request).join();
      if (text.isEmpty) {
        return {};
      }
      return Map<String, Object?>.from(jsonDecode(text) as Map);
    }

    Future<void> writeJson(HttpRequest request, Object body) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
      await request.response.close();
    }

    subscription = server.listen((request) async {
      if (request.headers.value('x-mytodo-token') != 'remote-token') {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/pair') {
        await readJson(request);
        await writeJson(request, {
          'deviceId': 'device-b',
          'name': 'Device B',
          'baseUrl': 'http://192.0.2.1:6553',
          'token': 'remote-token',
        });
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/sync/manifest') {
        await writeJson(request, {
          'deviceId': 'device-b',
          'clock': <String, int>{},
        });
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/sync/events') {
        await readJson(request);
        await writeJson(request, {
          'events': <Object>[],
          'clock': <String, int>{},
        });
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/sync/push') {
        final body = await readJson(request);
        final events = body['events'] as List<Object?>;
        for (final event in events) {
          final eventJson = Map<String, Object?>.from(event as Map);
          final payload = Map<String, Object?>.from(
            eventJson['payload'] as Map,
          );
          final title = payload['title'];
          if (title is String) {
            pushedTitles.add(title);
          }
        }
        await writeJson(request, {
          'applied': events.length,
          'clock': {'device-a': events.length},
        });
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final reachableUrl = 'http://127.0.0.1:${server.port}/';
    await sync.pairWith(baseUrl: reachableUrl, token: 'remote-token');

    expect(
      store.trustedDevices.single.baseUrl,
      reachableUrl.substring(0, reachableUrl.length - 1),
    );
    expect(pushedTitles, contains('Local before pairing'));
    expect(sync.status, contains('Synced Device B'));
  });
}
