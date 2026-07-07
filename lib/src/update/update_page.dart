import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Icons, SafeArea;
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
      content: SafeArea(
        child: FutureBuilder<UpdateCheckResult>(
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
              onRetry: _retry,
              onOpen: _open,
              service: _service,
            );
          },
        ),
      ),
    );
  }
}

void _showInfoBar(
  BuildContext context,
  String message,
  InfoBarSeverity severity,
) {
  displayInfoBar(
    context,
    builder: (ctx, close) =>
        InfoBar(title: Text(message), severity: severity, onClose: close),
  );
}

class _UpdateResultView extends StatelessWidget {
  const _UpdateResultView({
    required this.result,
    required this.mirror,
    required this.onMirrorChanged,
    required this.onRetry,
    required this.onOpen,
    required this.service,
  });

  final UpdateCheckResult result;
  final UpdateMirror mirror;
  final ValueChanged<UpdateMirror> onMirrorChanged;
  final VoidCallback onRetry;
  final Future<void> Function(Uri uri) onOpen;
  final AppUpdateService service;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final recommended = result.recommendedAsset;
    final checksum = result.checksumAsset;
    final installAssets = result.installAssets;
    final otherAssets = installAssets
        .where((asset) => asset.name != recommended?.name)
        .toList(growable: false);

    return ScaffoldPage(
      padding: EdgeInsets.zero,
      header: PageHeader(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('检查更新'),
      ),
      content: ColoredBox(
        color: theme.resources.solidBackgroundFillColorBase,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                _UpdateHero(result: result, onRetry: onRetry),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 760;
                    final download = recommended == null
                        ? _OpenReleasePanel(
                            releaseUrl: result.releaseUrl,
                            onOpen: onOpen,
                          )
                        : _PrimaryAssetPanel(
                            title: result.hasUpdate ? '推荐更新包' : '当前版本安装包',
                            asset: recommended,
                            mirror: mirror,
                            service: service,
                            onOpen: onOpen,
                          );
                    final settings = _DownloadSettingsPanel(
                      mirror: mirror,
                      checksum: checksum,
                      onMirrorChanged: onMirrorChanged,
                      onOpenChecksum: checksum == null
                          ? null
                          : () => onOpen(service.downloadUri(checksum, mirror)),
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          download,
                          const SizedBox(height: 12),
                          settings,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: download),
                        const SizedBox(width: 12),
                        Expanded(flex: 4, child: settings),
                      ],
                    );
                  },
                ),
                if (otherAssets.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _OtherAssetsPanel(
                    assets: otherAssets,
                    mirror: mirror,
                    service: service,
                    onOpen: onOpen,
                  ),
                ],
                if (result.releaseNotes.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _ReleaseNotesPanel(notes: result.releaseNotes.trim()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SurfacePanel extends StatelessWidget {
  const _SurfacePanel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _UpdateHero extends StatelessWidget {
  const _UpdateHero({required this.result, required this.onRetry});

  final UpdateCheckResult result;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final statusColor = result.hasUpdate
        ? accent
        : theme.resources.systemFillColorSuccess;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: result.hasUpdate
            ? accent.withValues(alpha: 0.10)
            : theme.resources.subtleFillColorTertiary,
        border: Border.all(
          color: result.hasUpdate
              ? accent.withValues(alpha: 0.28)
              : theme.resources.cardStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              result.hasUpdate ? Icons.system_update : Icons.verified,
              color: statusColor,
              size: 28,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 260, maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.hasUpdate ? '发现新版本' : '当前已是最新版本',
                  style: theme.typography.title?.copyWith(
                    color: theme.resources.textFillColorPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _VersionPill(label: '当前', value: result.currentVersion),
                    _VersionPill(label: '最新', value: result.latestVersion),
                  ],
                ),
              ],
            ),
          ),
          Button(
            onPressed: onRetry,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.refresh, size: 16),
                SizedBox(width: 8),
                Text('重新检查'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionPill extends StatelessWidget {
  const _VersionPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.resources.controlFillColorDefault,
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label $value',
        style: theme.typography.caption?.copyWith(
          color: theme.resources.textFillColorPrimary,
        ),
      ),
    );
  }
}

class _PrimaryAssetPanel extends StatelessWidget {
  const _PrimaryAssetPanel({
    required this.title,
    required this.asset,
    required this.mirror,
    required this.service,
    required this.onOpen,
  });

  final String title;
  final UpdateAsset asset;
  final UpdateMirror mirror;
  final AppUpdateService service;
  final Future<void> Function(Uri uri) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.download_for_offline, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: theme.typography.bodyStrong)),
            ],
          ),
          const SizedBox(height: 14),
          SelectableText(
            asset.name,
            style: theme.typography.body?.copyWith(
              color: theme.resources.textFillColorPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            asset.sizeLabel,
            style: TextStyle(color: theme.resources.textFillColorSecondary),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => onOpen(service.downloadUri(asset, mirror)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.download, size: 16),
                SizedBox(width: 8),
                Text('下载安装包'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenReleasePanel extends StatelessWidget {
  const _OpenReleasePanel({required this.releaseUrl, required this.onOpen});

  final String releaseUrl;
  final Future<void> Function(Uri uri) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Release 页面', style: theme.typography.bodyStrong),
          const SizedBox(height: 8),
          Text(
            '没有找到与当前平台匹配的安装包。',
            style: TextStyle(color: theme.resources.textFillColorSecondary),
          ),
          const SizedBox(height: 16),
          Button(
            onPressed: () => onOpen(Uri.parse(releaseUrl)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.open_in_new, size: 16),
                SizedBox(width: 8),
                Text('打开 Release 页面'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadSettingsPanel extends StatelessWidget {
  const _DownloadSettingsPanel({
    required this.mirror,
    required this.checksum,
    required this.onMirrorChanged,
    required this.onOpenChecksum,
  });

  final UpdateMirror mirror;
  final UpdateAsset? checksum;
  final ValueChanged<UpdateMirror> onMirrorChanged;
  final VoidCallback? onOpenChecksum;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          const SizedBox(height: 10),
          Text(
            mirror.description,
            style: TextStyle(color: theme.resources.textFillColorSecondary),
          ),
          if (!mirror.isOfficial) ...[
            const SizedBox(height: 12),
            const _WarningText('第三方镜像仅用于改善下载速度。下载后建议使用 SHA256 校验文件核对完整性。'),
          ],
          if (checksum != null) ...[
            const SizedBox(height: 16),
            Button(
              onPressed: onOpenChecksum,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.verified, size: 16),
                  SizedBox(width: 8),
                  Text('下载 SHA256'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OtherAssetsPanel extends StatelessWidget {
  const _OtherAssetsPanel({
    required this.assets,
    required this.mirror,
    required this.service,
    required this.onOpen,
  });

  final List<UpdateAsset> assets;
  final UpdateMirror mirror;
  final AppUpdateService service;
  final Future<void> Function(Uri uri) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return _SurfacePanel(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('其他安装包', style: theme.typography.bodyStrong),
          const SizedBox(height: 10),
          for (final asset in assets)
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
                          Text(
                            asset.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
    );
  }
}

class _ReleaseNotesPanel extends StatelessWidget {
  const _ReleaseNotesPanel({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('更新说明', style: theme.typography.bodyStrong),
          const SizedBox(height: 10),
          SelectableText(
            notes,
            style: TextStyle(
              color: theme.resources.textFillColorPrimary,
              height: 1.42,
            ),
          ),
        ],
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
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
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
        Icon(
          Icons.info_outline,
          size: 18,
          color: theme.resources.systemFillColorCaution,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}
