import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/todo_models.dart';
import '../data/todo_store.dart';

class SupabaseSyncConfig {
  const SupabaseSyncConfig({
    required this.enabled,
    required this.autoSync,
    required this.restUrl,
    required this.publishableKey,
    required this.tableName,
    required this.syncSpace,
  });

  static const defaultRestUrl = '';
  static const defaultPublishableKey = '';
  static const defaultTableName = 'mytodo_events';
  static const defaultSyncSpace = 'default';
  static const defaultAutoSync = true;

  final bool enabled;
  final bool autoSync;
  final String restUrl;
  final String publishableKey;
  final String tableName;
  final String syncSpace;

  bool get canSync =>
      enabled &&
      restUrl.trim().isNotEmpty &&
      publishableKey.trim().isNotEmpty &&
      tableName.trim().isNotEmpty &&
      syncSpace.trim().isNotEmpty;

  SupabaseSyncConfig copyWith({
    bool? enabled,
    bool? autoSync,
    String? restUrl,
    String? publishableKey,
    String? tableName,
    String? syncSpace,
  }) {
    return SupabaseSyncConfig(
      enabled: enabled ?? this.enabled,
      autoSync: autoSync ?? this.autoSync,
      restUrl: restUrl ?? this.restUrl,
      publishableKey: publishableKey ?? this.publishableKey,
      tableName: tableName ?? this.tableName,
      syncSpace: syncSpace ?? this.syncSpace,
    );
  }

  static SupabaseSyncConfig defaults() {
    return const SupabaseSyncConfig(
      enabled: false,
      autoSync: defaultAutoSync,
      restUrl: defaultRestUrl,
      publishableKey: defaultPublishableKey,
      tableName: defaultTableName,
      syncSpace: defaultSyncSpace,
    );
  }
}

class SupabaseSyncResult {
  const SupabaseSyncResult({required this.pulled, required this.pushed});

  final int pulled;
  final int pushed;
}

class SupabaseSyncService extends ChangeNotifier {
  static const _enabledKey = 'supabaseSync.enabled';
  static const _autoSyncKey = 'supabaseSync.autoSync';
  static const _restUrlKey = 'supabaseSync.restUrl';
  static const _publishableKeyKey = 'supabaseSync.publishableKey';
  static const _tableNameKey = 'supabaseSync.tableName';
  static const _syncSpaceKey = 'supabaseSync.syncSpace';
  static const _requestTimeout = Duration(seconds: 15);
  static const _autoSyncDelay = Duration(seconds: 6);
  static const _periodicAutoSyncInterval = Duration(minutes: 5);

  final TodoStore store;
  final http.Client _client;

  SupabaseSyncConfig _config = SupabaseSyncConfig.defaults();
  String _status = 'Supabase remote sync disabled';
  bool _busy = false;
  bool _closed = false;
  bool _ignoreStoreChanges = false;
  Timer? _autoSyncDebounce;
  Timer? _periodicAutoSync;

  SupabaseSyncService(this.store, {http.Client? client})
    : _client = client ?? http.Client() {
    store.addListener(_onStoreChanged);
  }

  SupabaseSyncConfig get config => _config;
  String get status => _status;
  bool get busy => _busy;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _config = SupabaseSyncConfig(
      enabled: prefs.getBool(_enabledKey) ?? false,
      autoSync:
          prefs.getBool(_autoSyncKey) ?? SupabaseSyncConfig.defaultAutoSync,
      restUrl:
          prefs.getString(_restUrlKey) ?? SupabaseSyncConfig.defaultRestUrl,
      publishableKey:
          prefs.getString(_publishableKeyKey) ??
          SupabaseSyncConfig.defaultPublishableKey,
      tableName:
          prefs.getString(_tableNameKey) ?? SupabaseSyncConfig.defaultTableName,
      syncSpace:
          prefs.getString(_syncSpaceKey) ?? SupabaseSyncConfig.defaultSyncSpace,
    );
    _setStatus(
      _config.enabled
          ? 'Supabase remote sync ready'
          : 'Supabase remote sync disabled',
    );
    _configureAutoSync();
  }

  Future<void> saveConfig(SupabaseSyncConfig config) async {
    final normalized = _normalizeConfig(config);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, normalized.enabled);
    await prefs.setBool(_autoSyncKey, normalized.autoSync);
    await prefs.setString(_restUrlKey, normalized.restUrl);
    await prefs.setString(_publishableKeyKey, normalized.publishableKey);
    await prefs.setString(_tableNameKey, normalized.tableName);
    await prefs.setString(_syncSpaceKey, normalized.syncSpace);
    _config = normalized;
    _setStatus(
      normalized.enabled
          ? 'Supabase remote sync ready'
          : 'Supabase remote sync disabled',
    );
    _configureAutoSync();
    if (normalized.canSync && normalized.autoSync) {
      _scheduleAutoSync();
    }
  }

  Future<void> testConnection() async {
    final config = _normalizeConfig(_config);
    _validateConfig(config, requireEnabled: false);
    await _runBusy('Testing Supabase connection', () async {
      final uri = _tableUri(config, {'select': 'event_id', 'limit': '1'});
      final response = await _client
          .get(uri, headers: _headers(config))
          .timeout(_requestTimeout);
      _throwIfBad(response);
      _setStatus('Supabase connection OK');
    });
  }

  Future<SupabaseSyncResult> syncNow() async {
    final config = _normalizeConfig(_config);
    _validateConfig(config);
    return _runBusy('Syncing with Supabase', () async {
      _ignoreStoreChanges = true;
      final remoteEvents = await _fetchRemoteEvents(config);
      final pulled = await store.applyRemoteEvents(remoteEvents);
      final localEvents = await store.allEvents();
      final pushed = await _pushLocalEvents(config, localEvents);
      _ignoreStoreChanges = false;
      _setStatus('Supabase synced: pulled $pulled, pushed $pushed');
      return SupabaseSyncResult(pulled: pulled, pushed: pushed);
    });
  }

  void _onStoreChanged() {
    if (_ignoreStoreChanges || _busy || !_config.canSync || !_config.autoSync) {
      return;
    }
    _scheduleAutoSync();
  }

  void _configureAutoSync() {
    _autoSyncDebounce?.cancel();
    _periodicAutoSync?.cancel();
    _autoSyncDebounce = null;
    _periodicAutoSync = null;
    if (!_config.canSync || !_config.autoSync) {
      return;
    }
    _periodicAutoSync = Timer.periodic(_periodicAutoSyncInterval, (_) {
      _scheduleAutoSync();
    });
  }

  void _scheduleAutoSync() {
    if (_closed || !_config.canSync || !_config.autoSync) {
      return;
    }
    _autoSyncDebounce?.cancel();
    _autoSyncDebounce = Timer(_autoSyncDelay, () {
      unawaited(_autoSyncNow());
    });
  }

  Future<void> _autoSyncNow() async {
    if (_closed || _busy || !_config.canSync || !_config.autoSync) {
      return;
    }
    try {
      await syncNow();
    } catch (_) {
      // Status is already updated by syncNow. Automatic sync should not surface
      // unhandled errors from background timers.
    }
  }

  Future<List<TodoEvent>> _fetchRemoteEvents(SupabaseSyncConfig config) async {
    final uri = _tableUri(config, {
      'sync_space': 'eq.${config.syncSpace}',
      'select': 'event_id,device_id,seq,timestamp,type,todo_id,payload_json',
      'order': 'timestamp.asc,seq.asc',
    });
    final response = await _client
        .get(uri, headers: _headers(config))
        .timeout(_requestTimeout);
    _throwIfBad(response);
    final rows = jsonDecode(response.body) as List;
    return rows
        .map(
          (row) => _eventFromSupabaseRow(Map<String, Object?>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<int> _pushLocalEvents(
    SupabaseSyncConfig config,
    List<TodoEvent> events,
  ) async {
    if (events.isEmpty) {
      return 0;
    }
    final uri = _tableUri(config, {'on_conflict': 'event_id'});
    final rows = events
        .map((event) => _eventToSupabaseRow(config.syncSpace, event))
        .toList(growable: false);
    final response = await _client
        .post(
          uri,
          headers: {
            ..._headers(config),
            'prefer': 'resolution=ignore-duplicates,return=minimal',
          },
          body: jsonEncode(rows),
        )
        .timeout(_requestTimeout);
    _throwIfBad(response);
    return events.length;
  }

  Map<String, String> _headers(SupabaseSyncConfig config) {
    return {
      'apikey': config.publishableKey,
      'authorization': 'Bearer ${config.publishableKey}',
      'content-type': 'application/json',
      'accept': 'application/json',
    };
  }

  Uri _tableUri(SupabaseSyncConfig config, Map<String, String> query) {
    final base = Uri.parse(config.restUrl);
    final path = [
      if (base.path.isNotEmpty) base.path.replaceFirst(RegExp(r'/$'), ''),
      config.tableName,
    ].join('/');
    return base.replace(path: path, queryParameters: query);
  }

  SupabaseSyncConfig _normalizeConfig(SupabaseSyncConfig config) {
    final restUrl = config.restUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final tableName = config.tableName.trim();
    return config.copyWith(
      restUrl: restUrl,
      publishableKey: config.publishableKey.trim(),
      tableName: tableName,
      syncSpace: config.syncSpace.trim(),
    );
  }

  void _validateConfig(
    SupabaseSyncConfig config, {
    bool requireEnabled = true,
  }) {
    if (requireEnabled && !config.enabled) {
      throw StateError('Supabase remote sync is disabled');
    }
    final restUri = Uri.tryParse(config.restUrl);
    final localHttp =
        restUri != null &&
        restUri.scheme == 'http' &&
        (restUri.host == '127.0.0.1' || restUri.host == 'localhost');
    if (restUri == null ||
        (restUri.scheme != 'https' && !localHttp) ||
        restUri.host.isEmpty ||
        !restUri.path.contains('/rest/v1')) {
      throw FormatException('Invalid Supabase REST URL');
    }
    if (config.publishableKey.isEmpty) {
      throw const FormatException('Missing publishable key');
    }
    if (config.publishableKey.startsWith('sb_secret_')) {
      throw const FormatException('Do not use a Supabase secret key here');
    }
    if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(config.tableName)) {
      throw const FormatException('Invalid Supabase table name');
    }
    if (config.syncSpace.isEmpty) {
      throw const FormatException('Missing sync space');
    }
  }

  TodoEvent _eventFromSupabaseRow(Map<String, Object?> row) {
    final payload = row['payload_json'];
    return TodoEvent(
      eventId: row['event_id'] as String,
      deviceId: row['device_id'] as String,
      seq: row['seq'] as int,
      timestamp: row['timestamp'] as int,
      type: row['type'] as String,
      todoId: row['todo_id'] as String,
      payload: payload is String
          ? Map<String, Object?>.from(jsonDecode(payload) as Map)
          : Map<String, Object?>.from(payload as Map),
    );
  }

  Map<String, Object?> _eventToSupabaseRow(String syncSpace, TodoEvent event) {
    return {
      'sync_space': syncSpace,
      'event_id': event.eventId,
      'device_id': event.deviceId,
      'seq': event.seq,
      'timestamp': event.timestamp,
      'type': event.type,
      'todo_id': event.todoId,
      'payload_json': event.payload,
    };
  }

  Future<T> _runBusy<T>(String status, Future<T> Function() action) async {
    if (_busy) {
      throw StateError('Supabase sync is already running');
    }
    _busy = true;
    _setStatus(status);
    try {
      return await action();
    } on TimeoutException {
      _setStatus('Supabase request timed out');
      rethrow;
    } on SocketException catch (error) {
      _setStatus('Supabase network error: ${error.message}');
      rethrow;
    } catch (error) {
      _setStatus('Supabase sync failed: $error');
      rethrow;
    } finally {
      _ignoreStoreChanges = false;
      _busy = false;
      notifyListeners();
    }
  }

  void _throwIfBad(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('${response.statusCode}: ${response.body}');
    }
  }

  void _setStatus(String value) {
    if (_closed) {
      return;
    }
    _status = value;
    notifyListeners();
  }

  void close() {
    _closed = true;
    store.removeListener(_onStoreChanged);
    _autoSyncDebounce?.cancel();
    _periodicAutoSync?.cancel();
    _client.close();
  }
}
