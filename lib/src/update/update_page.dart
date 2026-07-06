import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Icons;
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
      _showInfoBar(context, '无法打开链接: $uri', InfoBarSeverity.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      content: FutureBuilder<UpdateCheckResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: ProgressRing());
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

void _showInfoBar(BuildContext context, String message, InfoBarSeverity severity) {
  displayInfoBar(
    context,
    builder: (ctx, close) => InfoBar(
      title: Text(message),
      severity: severity,
      onClose: close,
    ),
  );
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
    final theme = FluentTheme.of(context);
    final recommended = result.recommendedAsset;
    final checksum = result.checksumAsset;
    final installAssets = result.installAssets;

    return ScaffoldPage(
      padding: const EdgeInsets.all(16),
      header: PageHeader(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('检查更新'),
      ),
      content: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            children: [
              _VersionCard(result: result),
              const SizedBox(height: 16),
              InfoLabel(
                label: '下载源',
                child: ComboBox<UpdateMirror>(
                  value: mirror,
                  isExpanded: true,
                  items: [
                    for (final candidate in AppUpdateService.mirrors)
                      ComboBoxItem<UpdateMirror>(
                        value: candidate,
                        child: Text(candidate.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      onMirrorChanged(value);
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                mirror.description,
                style: TextStyle(
                  color: theme.resources.textFillColorSecondary,
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
                Button(
                  onPressed: () => onOpen(Uri.parse(result.releaseUrl)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.open_in_new, size: 16),
                      SizedBox(width: 8),
                      Text('打开 Release 页面'),
                    ],
                  ),
                ),
              if (checksum != null) ...[
                const SizedBox(height: 12),
                Button(
                  onPressed: () => onOpen(service.downloadUri(checksum, mirror)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.verified, size: 16),
                      SizedBox(width: 8),
                      Text('下载 SHA256 校验文件'),
                    ],
                  ),
                ),
              ],
              if (installAssets.isNotEmpty) ...[
                const SizedBox(height: 16),
                Expander(
                  header: const Text('其他安装包'),
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final asset in installAssets)
                        if (asset.name != recommended?.name)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _HoverListTile(
                              onTap: () => onOpen(service.downloadUri(asset, mirror)),
                              child: Row(
                                children: [
                                  const Icon(Icons.download, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(asset.name),
                                        Text(
                                          asset.sizeLabel,
                                          style: TextStyle(
                                            color: theme.resources.textFillColorSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.open_in_new, size: 16),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ],
              if (result.releaseNotes.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('更新说明', style: theme.typography.bodyStrong),
                const SizedBox(height: 8),
                SelectableText(result.releaseNotes.trim()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HoverListTile extends StatefulWidget {
  const _HoverListTile({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_HoverListTile> createState() => _HoverListTileState();
}

class _HoverListTileState extends State<_HoverListTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: _hover && widget.onTap != null
                ? theme.resources.subtleFillColorSecondary
                : Color(0x00000000),
            borderRadius: BorderRadius.circular(6),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.result});

  final UpdateCheckResult result;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: result.hasUpdate
            ? accent.withValues(alpha: 0.12)
            : theme.resources.subtleFillColorTertiary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.hasUpdate ? Icons.system_update : Icons.check_circle,
                color: result.hasUpdate ? accent : accent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  result.hasUpdate ? '发现新版本' : '已是最新版本',
                  style: theme.typography.bodyStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('当前版本: ${result.currentVersion}'),
          Text('最新版本: ${result.latestVersion}'),
        ],
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
    final theme = FluentTheme.of(context);
    final button = primary
        ? FilledButton(
            onPressed: onOpen,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.download, size: 16),
                SizedBox(width: 8),
                Text('下载安装包'),
              ],
            ),
          )
        : Button(
            onPressed: onOpen,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.download, size: 16),
                SizedBox(width: 8),
                Text('下载'),
              ],
            ),
          );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.typography.bodyStrong),
          const SizedBox(height: 8),
          SelectableText(asset.name),
          const SizedBox(height: 4),
          Text(asset.sizeLabel),
          const SizedBox(height: 14),
          Align(alignment: Alignment.centerLeft, child: button),
        ],
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
    final theme = FluentTheme.of(context);
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
              Text('检查更新失败', style: theme.typography.title),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(
                    onPressed: onRetry,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.refresh, size: 16),
                        SizedBox(width: 8),
                        Text('重试'),
                      ],
                    ),
                  ),
                  Button(
                    onPressed: onOpenRelease,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.open_in_new, size: 16),
                        SizedBox(width: 8),
                        Text('打开 Release'),
                      ],
                    ),
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
    final theme = FluentTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: theme.resources.systemFillColorCaution),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}
