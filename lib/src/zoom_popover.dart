import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'zoom_layout_utils.dart';
import 'zoom_tier_icon.dart';

/// 档位调节卡片的文案配置，支持国际化与自定义文案。
class ZoomTierLabels {
  const ZoomTierLabels({
    this.listView = '列表视图',
    this.gridView = '网格视图',
    this.minimal = '极简',
    this.compact = '紧凑',
    this.standard = '标准',
    this.largeList = '大图',
    this.smallGrid = '小',
    this.mediumGrid = '中',
    this.largeGrid = '大',
    this.shortcutHint = 'Ctrl + 滚轮，或双指捏合，可逐档调节',
  });

  final String listView;
  final String gridView;
  final String minimal;
  final String compact;
  final String standard;
  final String largeList;
  final String smallGrid;
  final String mediumGrid;
  final String largeGrid;
  final String shortcutHint;

  static const ZoomTierLabels english = ZoomTierLabels(
    listView: 'List View',
    gridView: 'Grid View',
    minimal: 'Minimal',
    compact: 'Compact',
    standard: 'Standard',
    largeList: 'Large',
    smallGrid: 'Small',
    mediumGrid: 'Medium',
    largeGrid: 'Large',
    shortcutHint: 'Ctrl + Scroll or Pinch to adjust tiers',
  );

  String labelFor(FolderZoomTier tier) {
    return switch (tier) {
      FolderZoomTier.minimalList => minimal,
      FolderZoomTier.compactList => compact,
      FolderZoomTier.standardList => standard,
      FolderZoomTier.largeList => largeList,
      FolderZoomTier.smallGrid => smallGrid,
      FolderZoomTier.mediumGrid => mediumGrid,
      FolderZoomTier.largeGrid => largeGrid,
    };
  }
}

/// 在 [anchorContext] 所在控件下方弹出档位调节卡片。
Future<void> showZoomPopover(
  BuildContext anchorContext, {
  required double zoomScale,
  required ValueChanged<double> onZoomScaleChanged,
  bool listOnly = false,
  ZoomTierLabels labels = const ZoomTierLabels(),
}) async {
  final renderBox = anchorContext.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.maybeOf(anchorContext)?.context.findRenderObject() as RenderBox?;

  double topOffset = MediaQuery.paddingOf(anchorContext).top + 56.0;
  double rightOffset = 16.0;

  if (renderBox != null && overlay != null && renderBox.hasSize) {
    final globalPos = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    topOffset = globalPos.dy + renderBox.size.height + 6.0;
    final calculatedRight =
        overlay.size.width - (globalPos.dx + renderBox.size.width);
    rightOffset = calculatedRight.clamp(12.0, overlay.size.width - 280.0);
  }

  await showGeneralDialog<void>(
    context: anchorContext,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(anchorContext).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Stack(
        children: [
          Positioned(
            top: topOffset,
            right: rightOffset,
            child: ZoomPopoverCard(
              zoomScale: zoomScale,
              onZoomScaleChanged: onZoomScaleChanged,
              listOnly: listOnly,
              labels: labels,
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          alignment: Alignment.topRight,
          child: child,
        ),
      );
    },
  );
}

/// 滑杆 + 七档预设按钮的档位调节卡片。
class ZoomPopoverCard extends StatelessWidget {
  const ZoomPopoverCard({
    super.key,
    required this.zoomScale,
    required this.onZoomScaleChanged,
    this.listOnly = false,
    this.labels = const ZoomTierLabels(),
  });

  final double zoomScale;
  final ValueChanged<double> onZoomScaleChanged;
  final bool listOnly;
  final ZoomTierLabels labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tier = getFolderZoomTier(zoomScale);
    final isGrid = !listOnly && isFolderZoomGrid(zoomScale);

    final modeLabel = isGrid ? labels.gridView : labels.listView;
    final tierName = labels.labelFor(tier);

    final maxScale = listOnly ? kFolderZoomTierLargeList : 1.0;
    final divisions = listOnly ? 3 : (kFolderZoomTierValues.length - 1);

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 292,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh
                  .withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ZoomTierIcon(
                      zoomScale: zoomScale,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        modeLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        tierName,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.remove_rounded, size: 18),
                      onPressed: zoomScale > 0.001
                          ? () => onZoomScaleChanged(
                              stepFolderZoomScale(zoomScale, -1),
                            )
                          : null,
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                        ),
                        child: Slider(
                          value: snapFolderZoomScale(zoomScale)
                              .clamp(0.0, maxScale),
                          min: 0.0,
                          max: maxScale,
                          divisions: divisions,
                          onChanged: (val) =>
                              onZoomScaleChanged(snapFolderZoomScale(val)),
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      onPressed: zoomScale < (maxScale - 0.001)
                          ? () => onZoomScaleChanged(
                              stepFolderZoomScale(zoomScale, 1),
                            )
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ZoomTierPresetButton(
                      tier: FolderZoomTier.minimalList,
                      tooltip: '${labels.listView} · ${labels.minimal}',
                      isSelected: tier == FolderZoomTier.minimalList,
                      horizontalPadding: listOnly ? 16 : 9,
                      onTap: () =>
                          onZoomScaleChanged(kFolderZoomTierMinimalList),
                    ),
                    _ZoomTierPresetButton(
                      tier: FolderZoomTier.compactList,
                      tooltip: '${labels.listView} · ${labels.compact}',
                      isSelected: tier == FolderZoomTier.compactList,
                      horizontalPadding: listOnly ? 16 : 9,
                      onTap: () =>
                          onZoomScaleChanged(kFolderZoomTierCompactList),
                    ),
                    _ZoomTierPresetButton(
                      tier: FolderZoomTier.standardList,
                      tooltip: '${labels.listView} · ${labels.standard}',
                      isSelected: tier == FolderZoomTier.standardList,
                      horizontalPadding: listOnly ? 16 : 9,
                      onTap: () =>
                          onZoomScaleChanged(kFolderZoomTierStandardList),
                    ),
                    _ZoomTierPresetButton(
                      tier: FolderZoomTier.largeList,
                      tooltip: '${labels.listView} · ${labels.largeList}',
                      isSelected: tier == FolderZoomTier.largeList,
                      horizontalPadding: listOnly ? 16 : 9,
                      onTap: () =>
                          onZoomScaleChanged(kFolderZoomTierLargeList),
                    ),
                    if (!listOnly) ...[
                      Container(
                        width: 1,
                        height: 18,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.5),
                      ),
                      _ZoomTierPresetButton(
                        tier: FolderZoomTier.smallGrid,
                        tooltip: '${labels.gridView} · ${labels.smallGrid}',
                        isSelected: tier == FolderZoomTier.smallGrid,
                        onTap: () =>
                            onZoomScaleChanged(kFolderZoomTierSmallGrid),
                      ),
                      _ZoomTierPresetButton(
                        tier: FolderZoomTier.mediumGrid,
                        tooltip: '${labels.gridView} · ${labels.mediumGrid}',
                        isSelected: tier == FolderZoomTier.mediumGrid,
                        onTap: () =>
                            onZoomScaleChanged(kFolderZoomTierMediumGrid),
                      ),
                      _ZoomTierPresetButton(
                        tier: FolderZoomTier.largeGrid,
                        tooltip: '${labels.gridView} · ${labels.largeGrid}',
                        isSelected: tier == FolderZoomTier.largeGrid,
                        onTap: () =>
                            onZoomScaleChanged(kFolderZoomTierLargeGrid),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.mouse_rounded,
                      size: 13,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.75),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        labels.shortcutHint,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomTierPresetButton extends StatelessWidget {
  const _ZoomTierPresetButton({
    required this.tier,
    required this.isSelected,
    required this.onTap,
    this.tooltip,
    this.horizontalPadding = 9.0,
  });

  final FolderZoomTier tier;
  final bool isSelected;
  final VoidCallback onTap;
  final String? tooltip;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.16)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.6)
                : Colors.transparent,
          ),
        ),
        child: ZoomTierIcon(
          tier: tier,
          size: 16,
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// 通用档位按钮：工具栏与顶栏都能直接放置。
class ZoomButton extends StatelessWidget {
  const ZoomButton({
    super.key,
    required this.zoomScale,
    required this.onZoomScaleChanged,
    this.iconSize = 24.0,
    this.color,
    this.visualDensity,
    this.listOnly = false,
    this.labels = const ZoomTierLabels(),
  });

  final double zoomScale;
  final ValueChanged<double> onZoomScaleChanged;
  final double iconSize;
  final Color? color;
  final VisualDensity? visualDensity;
  final bool listOnly;
  final ZoomTierLabels labels;

  @override
  Widget build(BuildContext context) {
    final isGrid = !listOnly && isFolderZoomGrid(zoomScale);
    final tooltipText = listOnly ? labels.listView : (isGrid ? labels.gridView : labels.listView);

    return Builder(
      builder: (btnContext) {
        return IconButton(
          tooltip: tooltipText,
          visualDensity: visualDensity,
          onPressed: () => showZoomPopover(
            btnContext,
            zoomScale: zoomScale,
            onZoomScaleChanged: onZoomScaleChanged,
            listOnly: listOnly,
            labels: labels,
          ),
          icon: ZoomTierIcon(
            zoomScale: zoomScale,
            size: iconSize,
            color: color,
          ),
        );
      },
    );
  }
}
