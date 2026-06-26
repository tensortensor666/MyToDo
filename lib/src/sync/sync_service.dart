import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../data/todo_models.dart';
import '../data/todo_store.dart';

class DiscoveredPeer {
  const DiscoveredPeer({
    required this.deviceId,
    required this.name,
    required this.baseUrl,
    required this.trusted,
    required this.lastSeenAt,
  });

  final String deviceId;
  final String name;
  final String baseUrl;
  final bool trusted;
  final int lastSeenAt;
}

class PairingInfo {
  const PairingInfo({
    required this.deviceId,
    required this.name,
    required this.baseUrl,
    required this.token,
  });

  final String deviceId;
  final String name;
  final String baseUrl;
  final String token;

  String toQrData() {
    return jsonEncode({
      'app': 'mytodo',
      'deviceId': deviceId,
      'name': name,
      'baseUrl': baseUrl,
      'token': token,
    });
  }
}

class SyncService extends ChangeNotifier {
  SyncService(this.store, {this.enableMdns = true});

  static const serviceType = '_mytodo._tcp';
  static const protocolVersion = '1';
  static const _requestTimeout = Duration(seconds: 8);

  final TodoStore store;
  final bool enableMdns;
  final _client = http.Client();
  final Map<String, DiscoveredPeer> _discovered = {};

  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;
  String _status = 'Starting sync service';
  String? _localBaseUrl;
  bool _started = false;

  List<DiscoveredPeer> get discoveredPeers {
    final peers = _discovered.values.toList(growable: false);
    peers.sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    return peers;
  }

  String get status => _status;
  String? get localBaseUrl => _localBaseUrl;

  PairingInfo? get pairingInfo {
    final baseUrl = _localBaseUrl;
    if (baseUrl == null) {
      return null;
    }
    return PairingInfo(
      deviceId: store.device.deviceId,
      name: store.device.name,
      baseUrl: baseUrl,
      token: store.device.token,
    );
  }

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    await _startHttpServer();
    if (enableMdns) {
      try {
        await _startMdns();
      } catch (error) {
        _setStatus(
          'Sync service ready at $_localBaseUrl; LAN discovery unavailable: $error',
        );
        return;
      }
    }
    _setStatus('Sync service ready at $_localBaseUrl');
  }

  Future<void> stop() async {
    await _discoverySub?.cancel();
    await _discovery?.stop();
    await _broadcast?.stop();
    await _server?.close(force: true);
    _client.close();
  }

  Future<void> _startHttpServer() async {
    final router = Router()
      ..get('/health', _health)
      ..post('/pair', _pair)
      ..get('/sync/manifest', _manifest)
      ..post('/sync/events', _eventsAfterClock)
      ..post('/sync/push', _pushEvents);

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 0);
    final port = _server!.port;
    final host = await _bestLocalAddress();
    _localBaseUrl = 'http://$host:$port';
  }

  Future<void> _startMdns() async {
    final baseUrl = _localBaseUrl;
    if (baseUrl == null) {
      return;
    }
    final port = _server!.port;
    final service = BonsoirService(
      name: 'MyTodo ${store.device.name}',
      type: serviceType,
      port: port,
      attributes: {
        'did': store.device.deviceId,
        'name': store.device.name,
        'proto': protocolVersion,
      },
    );
    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.initialize();
    await _broadcast!.start();

    _discovery = BonsoirDiscovery(type: serviceType);
    await _discovery!.initialize();
    _discoverySub = _discovery!.eventStream?.listen(_onDiscoveryEvent);
    await _discovery!.start();
  }

  Future<void> _onDiscoveryEvent(BonsoirDiscoveryEvent event) async {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        await event.service.resolve(_discovery!.serviceResolver);
      case BonsoirDiscoveryServiceResolvedEvent():
      case BonsoirDiscoveryServiceUpdatedEvent():
        final service = event.service;
        if (service != null) {
          await _rememberResolvedService(service);
        }
      case BonsoirDiscoveryServiceLostEvent():
        final deviceId = event.service.attributes['did'];
        if (deviceId != null) {
          _discovered.remove(deviceId);
          notifyListeners();
        }
      default:
        break;
    }
  }

  Future<void> _rememberResolvedService(BonsoirService service) async {
    final deviceId = service.attributes['did'];
    if (deviceId == null || deviceId == store.device.deviceId) {
      return;
    }
    final host = service.hostAddress;
    if (host == null || host.isEmpty) {
      return;
    }
    final name = service.attributes['name'] ?? service.name;
    final baseUrl = 'http://$host:${service.port}';
    final trusted = store.trustedDeviceById(deviceId);
    final peer = DiscoveredPeer(
      deviceId: deviceId,
      name: name,
      baseUrl: baseUrl,
      trusted: trusted != null,
      lastSeenAt: DateTime.now().millisecondsSinceEpoch,
    );
    _discovered[deviceId] = peer;
    notifyListeners();

    if (trusted != null) {
      final updatedTrusted = TrustedDevice(
        deviceId: trusted.deviceId,
        name: name,
        baseUrl: baseUrl,
        token: trusted.token,
        lastSeenAt: peer.lastSeenAt,
      );
      await store.upsertTrustedDevice(updatedTrusted);
      await syncWithTrustedDevice(updatedTrusted);
    }
  }

  Future<Response> _health(Request request) async {
    return _json({
      'app': 'mytodo',
      'deviceId': store.device.deviceId,
      'name': store.device.name,
      'baseUrl': _localBaseUrl,
      'protocol': protocolVersion,
    });
  }

  Future<Response> _pair(Request request) async {
    final auth = _requireLocalToken(request);
    if (auth != null) {
      return auth;
    }
    final body = await _readJson(request);
    final peerDeviceId = body['deviceId'] as String?;
    final peerName = body['name'] as String?;
    final peerBaseUrl = body['baseUrl'] as String?;
    final peerToken = body['token'] as String?;
    if (peerDeviceId == null ||
        peerName == null ||
        peerBaseUrl == null ||
        peerToken == null) {
      return Response.badRequest(body: 'Invalid pairing payload');
    }
    late final String normalizedPeerBaseUrl;
    try {
      normalizedPeerBaseUrl = _normalizeBaseUrl(peerBaseUrl);
    } on FormatException catch (error) {
      return Response.badRequest(body: error.message);
    }
    await store.upsertTrustedDevice(
      TrustedDevice(
        deviceId: peerDeviceId,
        name: peerName,
        baseUrl: normalizedPeerBaseUrl,
        token: peerToken,
        lastSeenAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    return _json({
      'deviceId': store.device.deviceId,
      'name': store.device.name,
      'baseUrl': _localBaseUrl,
      'token': store.device.token,
    });
  }

  Future<Response> _manifest(Request request) async {
    final auth = _requireLocalToken(request);
    if (auth != null) {
      return auth;
    }
    return _json({
      'deviceId': store.device.deviceId,
      'clock': await store.eventClock(),
    });
  }

  Future<Response> _eventsAfterClock(Request request) async {
    final auth = _requireLocalToken(request);
    if (auth != null) {
      return auth;
    }
    final body = await _readJson(request);
    final clock = _parseClock(body['clock']);
    final events = await store.eventsAfterClock(clock);
    return _json({
      'events': events.map((event) => event.toJson()).toList(),
      'clock': await store.eventClock(),
    });
  }

  Future<Response> _pushEvents(Request request) async {
    final auth = _requireLocalToken(request);
    if (auth != null) {
      return auth;
    }
    final body = await _readJson(request);
    final events = _parseEvents(body['events']);
    final applied = await store.applyRemoteEvents(events);
    return _json({'applied': applied, 'clock': await store.eventClock()});
  }

  Response? _requireLocalToken(Request request) {
    final token = request.headers['x-mytodo-token'];
    if (token != store.device.token) {
      return Response.forbidden('Invalid pairing token');
    }
    return null;
  }

  Future<void> pairWithQrData(String data) async {
    final decoded = jsonDecode(data) as Map<String, Object?>;
    if (decoded['app'] != 'mytodo') {
      throw FormatException('Not a MyTodo pairing code');
    }
    final baseUrl = decoded['baseUrl'];
    final token = decoded['token'];
    if (baseUrl is! String || token is! String) {
      throw FormatException('Invalid MyTodo pairing code');
    }
    await pairWith(baseUrl: baseUrl, token: token);
  }

  Future<void> pairWith({
    required String baseUrl,
    required String token,
  }) async {
    final info = pairingInfo;
    if (info == null) {
      throw StateError('Sync service is not ready');
    }
    final normalizedBaseUrl = _normalizeBaseUrl(baseUrl);
    _setStatus('Pairing with $normalizedBaseUrl');
    final response = await _client
        .post(
          Uri.parse('$normalizedBaseUrl/pair'),
          headers: _headers(token),
          body: jsonEncode({
            'deviceId': info.deviceId,
            'name': info.name,
            'baseUrl': info.baseUrl,
            'token': info.token,
          }),
        )
        .timeout(_requestTimeout);
    _throwIfBad(response);
    final body = jsonDecode(response.body) as Map<String, Object?>;
    final trusted = TrustedDevice(
      deviceId: body['deviceId'] as String,
      name: body['name'] as String,
      baseUrl: normalizedBaseUrl,
      token: body['token'] as String,
      lastSeenAt: DateTime.now().millisecondsSinceEpoch,
    );
    await store.upsertTrustedDevice(trusted);
    await syncWithTrustedDevice(trusted, throwOnFailure: true);
  }

  Future<void> syncAllTrustedDevices() async {
    for (final device in store.trustedDevices) {
      await syncWithTrustedDevice(device);
    }
  }

  Future<void> syncWithTrustedDevice(
    TrustedDevice peer, {
    bool throwOnFailure = false,
  }) async {
    try {
      final peerBaseUrl = _normalizeBaseUrl(peer.baseUrl);
      _setStatus('Syncing with ${peer.name}');
      final manifestResponse = await _client
          .get(
            Uri.parse('$peerBaseUrl/sync/manifest'),
            headers: _headers(peer.token),
          )
          .timeout(_requestTimeout);
      _throwIfBad(manifestResponse);
      final manifest =
          jsonDecode(manifestResponse.body) as Map<String, Object?>;
      final remoteClock = _parseClock(manifest['clock']);

      final pullResponse = await _client
          .post(
            Uri.parse('$peerBaseUrl/sync/events'),
            headers: _headers(peer.token),
            body: jsonEncode({'clock': await store.eventClock()}),
          )
          .timeout(_requestTimeout);
      _throwIfBad(pullResponse);
      final pullBody = jsonDecode(pullResponse.body) as Map<String, Object?>;
      final pulled = _parseEvents(pullBody['events']);
      final applied = await store.applyRemoteEvents(pulled);

      final eventsToPush = await store.eventsAfterClock(remoteClock);
      final pushResponse = await _client
          .post(
            Uri.parse('$peerBaseUrl/sync/push'),
            headers: _headers(peer.token),
            body: jsonEncode({
              'events': eventsToPush.map((event) => event.toJson()).toList(),
            }),
          )
          .timeout(_requestTimeout);
      _throwIfBad(pushResponse);

      await store.upsertTrustedDevice(
        TrustedDevice(
          deviceId: peer.deviceId,
          name: peer.name,
          baseUrl: peerBaseUrl,
          token: peer.token,
          lastSeenAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      _setStatus(
        'Synced ${peer.name}: pulled $applied, pushed ${eventsToPush.length}',
      );
    } catch (error) {
      _setStatus('Sync failed for ${peer.name}: $error');
      if (throwOnFailure) {
        rethrow;
      }
    }
  }

  Map<String, String> _headers(String token) {
    return {'content-type': 'application/json', 'x-mytodo-token': token};
  }

  Future<Map<String, Object?>> _readJson(Request request) async {
    final text = await request.readAsString();
    if (text.isEmpty) {
      return {};
    }
    return Map<String, Object?>.from(jsonDecode(text) as Map);
  }

  Map<String, int> _parseClock(Object? value) {
    if (value is! Map) {
      return {};
    }
    return value.map((key, value) => MapEntry(key as String, value as int));
  }

  List<TodoEvent> _parseEvents(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map(
          (event) =>
              TodoEvent.fromJson(Map<String, Object?>.from(event as Map)),
        )
        .toList(growable: false);
  }

  Response _json(Object value) {
    return Response.ok(
      jsonEncode(value),
      headers: {'content-type': 'application/json'},
    );
  }

  void _throwIfBad(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('${response.statusCode}: ${response.body}');
    }
  }

  String _normalizeBaseUrl(String value) {
    final uri = Uri.parse(value.trim());
    if (!uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw FormatException('Invalid device address: $value');
    }
    return uri.replace(path: '', query: null, fragment: null).toString();
  }

  void _setStatus(String value) {
    _status = value;
    notifyListeners();
  }

  Future<String> _bestLocalAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.isLoopback) {
          continue;
        }
        final text = address.address;
        if (text.startsWith('192.168.') ||
            text.startsWith('10.') ||
            _is172Private(text)) {
          return text;
        }
      }
    }
    for (final interface in interfaces) {
      if (interface.addresses.isNotEmpty) {
        return interface.addresses.first.address;
      }
    }
    return InternetAddress.loopbackIPv4.address;
  }

  bool _is172Private(String address) {
    final parts = address.split('.');
    if (parts.length != 4 || parts.first != '172') {
      return false;
    }
    final second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }
}
