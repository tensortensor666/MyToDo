import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update_service.dart';

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  final AppUpdateService _service = AppUpdateService();
  late Future<UpdateCheckResult> _future = _service.checkLatest();
  late UpdateMirror _mirror = AppUpdateService.recommendedDownloadMirror();

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _future = _service.checkLatest();
    });
  }

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法打开链接: $uri')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('检查更新')),
      body: FutureBuilder<UpdateCheckResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _UpdateError(
              message: snapshot.error.toString(),
              onRetry: _retry,
              onOpenRelease: () => _open(
                Uri.parse(
                  'https://github.com/${AppUpdateService.repository}/releases/latest',
                ),
              ),
            );
          }
          return _UpdateResultView(
            result: snapshot.requireData,
            mirror: _mirror,
            onMirrorChanged: (mirror) {
              setState(() {
                _mirror = mirror;
              });
            },
            onOpen: _open,
            service: _service,
          );
        },
      ),
    );
  }
}

class _UpdateResultView extends StatelessWidget {
  const _UpdateResultView({
    required this.result,
    required this.mirror,
    required this.onMirrorChanged,
    required this.onOpen,
    required this.service,
  });

  final UpdateCheckResult result;
  final UpdateMirror mirror;
  final ValueChanged<UpdateMirror> onMirrorChanged;
  final Future<void> Function(Uri uri) onOpen;
  final AppUpdateService service;

  @override
  Widget build(BuildContext context) {
    final recommended = result.recommendedAsset;
    final checksum = result.checksumAsset;
    final installAssets = result.installAssets;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _VersionCard(result: result),
        const SizedBox(height: 16),
        DropdownButtonFormField<UpdateMirror>(
          initialValue: mirror,
          decoration: const InputDecoration(
            labelText: '下载源',
            prefixIcon: Icon(Icons.public),
          ),
          items: [
            for (final candidate in AppUpdateService.mirrors)
              DropdownMenuItem(value: candidate, child: Text(candidate.label)),
          ],
          onChanged: (value) {
            if (value != null) {
              onMirrorChanged(value);
            }
          },
        ),
        const SizedBox(height: 8),
        Text(
          mirror.description,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (!mirror.isOfficial) ...[
          const SizedBox(height: 8),
          const _WarningText('国内加速为第三方镜像，仅用于改善下载速度。下载后可用 SHA256 校验文件核对完整性。'),
        ],
        const SizedBox(height: 16),
        if (recommended != null)
          _AssetCard(
            title: result.hasUpdate ? '推荐更新包' : '当前版本安装包',
            asset: recommended,
            primary: true,
            onOpen: () => onOpen(service.downloadUri(recommended, mirror)),
          )
        else
          OutlinedButton.icon(
            onPressed: () => onOpen(Uri.parse(result.releaseUrl)),
            icon: const Icon(Icons.open_in_new),
            label: const Text('打开 Release 页面'),
          ),
        if (checksum != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => onOpen(service.downloadUri(checksum, mirror)),
            icon: const Icon(Icons.verified),
            label: const Text('下载 SHA256 校验文件'),
          ),
        ],
        if (installAssets.isNotEmpty) ...[
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('其他安装包'),
            children: [
              for (final asset in installAssets)
                if (asset.name != recommended?.name)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.download),
                    title: Text(asset.name),
                    subtitle: Text(asset.sizeLabel),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => onOpen(service.downloadUri(asset, mirror)),
                  ),
            ],
          ),
        ],
        if (result.releaseNotes.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('更新说明', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SelectableText(result.releaseNotes.trim()),
        ],
      ],
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.result});

  final UpdateCheckResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: result.hasUpdate
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.hasUpdate ? Icons.system_update : Icons.check_circle,
                  color: result.hasUpdate
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    result.hasUpdate ? '发现新版本' : '已是最新版本',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('当前版本: ${result.currentVersion}'),
            Text('最新版本: ${result.latestVersion}'),
          ],
        ),
      ),
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({
    required this.title,
    required this.asset,
    required this.onOpen,
    this.primary = false,
  });

  final String title;
  final UpdateAsset asset;
  final VoidCallback onOpen;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final button = primary
        ? FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.download),
            label: const Text('下载安装包'),
          )
        : OutlinedButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.download),
            label: const Text('下载'),
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(asset.name),
            const SizedBox(height: 4),
            Text(asset.sizeLabel),
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerLeft, child: button),
          ],
        ),
      ),
    );
  }
}

class _UpdateError extends StatelessWidget {
  const _UpdateError({
    required this.message,
    required this.onRetry,
    required this.onOpenRelease,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onOpenRelease;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 44),
              const SizedBox(height: 16),
              Text('检查更新失败', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onOpenRelease,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('打开 Release'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningText extends StatelessWidget {
  const _WarningText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 18,
          color: Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}
