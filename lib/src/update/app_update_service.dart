import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateMirror {
  const UpdateMirror({
    required this.id,
    required this.label,
    required this.description,
    this.prefix = '',
  });

  final String id;
  final String label;
  final String description;
  final String prefix;

  bool get isOfficial => prefix.isEmpty;

  Uri resolve(String url) {
    if (isOfficial) {
      return Uri.parse(url);
    }
    return Uri.parse('$prefix$url');
  }
}

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  final String name;
  final String downloadUrl;
  final int sizeBytes;

  String get sizeLabel {
    final mb = sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.releaseNotes,
    required this.assets,
    required this.metadataSource,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseUrl;
  final String releaseNotes;
  final List<UpdateAsset> assets;
  final String metadataSource;

  bool get hasUpdate =>
      AppUpdateService.compareVersions(latestVersion, currentVersion) > 0;

  UpdateAsset? get recommendedAsset {
    if (kIsWeb) return null;
    if (Platform.isWindows) {
      return _firstAssetContaining(['windows-x64-setup.exe']) ??
          _firstAssetContaining(['windows-x64.zip']);
    }
    if (Platform.isAndroid) {
      return _firstAssetContaining(['arm64-v8a.apk']) ??
          _firstAssetContaining(['armeabi-v7a.apk']) ??
          _firstAssetContaining(['x86_64.apk']);
    }
    return null;
  }

  UpdateAsset? get checksumAsset => _firstAssetContaining(['sha256sums']);

  List<UpdateAsset> get installAssets {
    return assets
        .where((asset) {
          final name = asset.name.toLowerCase();
          return name.endsWith('.apk') ||
              name.endsWith('.exe') ||
              name.endsWith('.zip');
        })
        .toList(growable: false);
  }

  UpdateAsset? _firstAssetContaining(List<String> needles) {
    for (final needle in needles) {
      for (final asset in assets) {
        if (asset.name.toLowerCase().contains(needle)) {
          return asset;
        }
      }
    }
    return null;
  }
}

class AppUpdateService {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  static const repository = 'tensortensor666/MyToDo';
  static const mirrors = [
    UpdateMirror(
      id: 'official',
      label: 'GitHub 官方',
      description: '官方下载源，最可信但国内网络可能较慢。',
    ),
    UpdateMirror(
      id: 'gh-llkk',
      label: '国内加速 1',
      description: '第三方 GitHub 加速镜像，适合官方下载较慢时使用。',
      prefix: 'https://gh.llkk.cc/',
    ),
    UpdateMirror(
      id: 'ghproxy',
      label: '国内加速 2',
      description: '第三方 GitHub 加速镜像，稳定性取决于镜像服务。',
      prefix: 'https://ghproxy.net/',
    ),
    UpdateMirror(
      id: 'gh-proxy',
      label: '国内加速 3',
      description: '第三方 GitHub 加速镜像，适合临时备用。',
      prefix: 'https://gh-proxy.com/',
    ),
  ];

  static const _releaseApiUrls = [
    'https://api.github.com/repos/$repository/releases/latest',
    'https://gh.llkk.cc/https://api.github.com/repos/$repository/releases/latest',
    'https://ghproxy.net/https://api.github.com/repos/$repository/releases/latest',
    'https://gh-proxy.com/https://api.github.com/repos/$repository/releases/latest',
  ];

  final http.Client _client;

  static UpdateMirror recommendedDownloadMirror({
    String? languageCode,
    String? countryCode,
  }) {
    final locale = PlatformDispatcher.instance.locale;
    final language = (languageCode ?? locale.languageCode).toLowerCase();
    final country = (countryCode ?? locale.countryCode ?? '').toUpperCase();
    if (language == 'zh' || country == 'CN') {
      return mirrors[1];
    }
    return mirrors.first;
  }

  Future<UpdateCheckResult> checkLatest() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    Object? lastError;
    for (final url in _releaseApiUrls) {
      try {
        final response = await _client
            .get(
              Uri.parse(url),
              headers: const {
                'accept': 'application/vnd.github+json',
                'user-agent': 'MyTodo update checker',
              },
            )
            .timeout(const Duration(seconds: 12));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('HTTP ${response.statusCode}');
        }

        final body = jsonDecode(response.body) as Map<String, Object?>;
        final tag = (body['tag_name'] as String? ?? '').trim();
        if (tag.isEmpty) {
          throw const FormatException('Missing release tag');
        }
        final assetsJson = body['assets'];
        if (assetsJson is! List) {
          throw const FormatException('Missing release assets');
        }

        return UpdateCheckResult(
          currentVersion: currentVersion,
          latestVersion: _normalizeVersion(tag),
          releaseUrl:
              body['html_url'] as String? ??
              'https://github.com/$repository/releases/latest',
          releaseNotes: body['body'] as String? ?? '',
          assets: assetsJson
              .whereType<Map>()
              .map((asset) {
                final name = asset['name'] as String? ?? '';
                final downloadUrl = asset['browser_download_url'] as String?;
                if (name.isEmpty || downloadUrl == null) {
                  return null;
                }
                return UpdateAsset(
                  name: name,
                  downloadUrl: downloadUrl,
                  sizeBytes: asset['size'] as int? ?? 0,
                );
              })
              .nonNulls
              .toList(growable: false),
          metadataSource: url,
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('检查更新失败: $lastError');
  }

  Uri downloadUri(UpdateAsset asset, UpdateMirror mirror) {
    return mirror.resolve(asset.downloadUrl);
  }

  void close() {
    _client.close();
  }

  static int compareVersions(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var i = 0; i < length; i++) {
      final leftValue = i < leftParts.length ? leftParts[i] : 0;
      final rightValue = i < rightParts.length ? rightParts[i] : 0;
      if (leftValue != rightValue) {
        return leftValue.compareTo(rightValue);
      }
    }
    return 0;
  }

  static String _normalizeVersion(String value) {
    return value.trim().replaceFirst(RegExp('^v', caseSensitive: false), '');
  }

  static List<int> _versionParts(String value) {
    final normalized = _normalizeVersion(value).split(RegExp(r'[+-]')).first;
    return normalized
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }
}
