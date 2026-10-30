import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'zoom_item_scaffold.dart';
import 'zoom_layout_utils.dart';

/// 网格卡片的统一悬停反馈：指针进入时轻微放大。
class HoverableCard extends StatefulWidget {
  const HoverableCard({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;

  /// 是否启用悬停轻微放大反馈。
  ///
  /// 在列表与网格动态切换过渡时保持此组件始终挂载在树上（仅通过 [enabled] 开关），
  /// 避免 Widget 树根节点 RuntimeType 突变导致整屏条目 unmount / remount。
  final bool enabled;

  @override
  State<HoverableCard> createState() => _HoverableCardState();
}

class _HoverableCardState extends State<HoverableCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: widget.enabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _isHovered = false) : null,
      child: AnimatedScale(
        scale: (widget.enabled && _isHovered) ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// A reusable floating circular play button that appears over cover art on hover.
class CoverPlayButton extends StatefulWidget {
  const CoverPlayButton({
    super.key,
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  final double size;
  final double iconSize;
  final VoidCallback onTap;

  @override
  State<CoverPlayButton> createState() => _CoverPlayButtonState();
}

class _CoverPlayButtonState extends State<CoverPlayButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: _isHovered ? 0.50 : 0.36),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(left: 1.5),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: widget.iconSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Unified cover wrapper for zoom items across List and Grid tiers.
///
/// Encapsulates:
/// - Smooth corner radius interpolation between list and grid tiers.
/// - Circular clipping option for artist avatars.
/// - Unified multi-selection overlay (semi-transparent container + smooth Checkbox morphing).
/// - Optional grid-mode hover play button ([CoverPlayButton]).
/// - Optional highlighted border indicator.
class ZoomItemCover extends StatefulWidget {
  const ZoomItemCover({
    super.key,
    required this.child,
    required this.metrics,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isHighlighted = false,
    this.isCircle = false,
    this.borderRadius,
    this.onToggleSelect,
    this.onPlay,
    this.badge,
    this.centerCheckboxInGrid = false,
    this.selectionOverlayColor,
  });

  /// The underlying cover content.
  final Widget child;

  /// Current zoom layout metrics driving morph progress.
  final FolderZoomLayoutMetrics metrics;

  /// Whether this item is currently selected in multi-selection mode.
  final bool isSelected;

  /// Whether global or local multi-selection mode is active.
  final bool isSelectionMode;

  /// Whether this item is currently highlighted (e.g. keyboard navigation or search target).
  final bool isHighlighted;

  /// Whether to clip this cover as a circle (e.g. for avatars).
  final bool isCircle;

  /// Custom border radius override. If null, smoothly lerps from 8.0 to 12.0.
  final BorderRadius? borderRadius;

  /// Callback when toggling selection.
  final VoidCallback? onToggleSelect;

  /// Optional play callback. When non-null, shows a hover play button in grid tiers.
  final VoidCallback? onPlay;

  /// Optional badge widget positioned over the cover.
  final Widget? badge;

  /// Whether the checkbox should stay centered in grid mode (e.g. for circular avatars).
  final bool centerCheckboxInGrid;

  /// Color override for the selection overlay.
  final Color? selectionOverlayColor;

  @override
  State<ZoomItemCover> createState() => _ZoomItemCoverState();
}

class _ZoomItemCoverState extends State<ZoomItemCover> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveMetrics =
        ZoomItemEffectiveMetrics.maybeOf(context) ?? widget.metrics;
    final gridMorph = effectiveMetrics.gridMorph;
    final isGridTarget = effectiveMetrics.isGridTarget;

    final coverRadiusValue = lerpDouble(8.0, 12.0, gridMorph)!;
    final effectiveRadius =
        widget.borderRadius ?? BorderRadius.circular(coverRadiusValue);

    final overlayColor = widget.selectionOverlayColor ??
        (widget.isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : Colors.black26);

    final checkboxGridAlign = widget.centerCheckboxInGrid
        ? Alignment.center
        : Alignment.topLeft;
    final checkboxAlign = Alignment.lerp(
      Alignment.center,
      checkboxGridAlign,
      gridMorph,
    )!;

    final checkboxPadding = widget.centerCheckboxInGrid
        ? EdgeInsets.zero
        : EdgeInsets.all(lerpDouble(0.0, 8.0, gridMorph)!);

    final content = ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (widget.badge != null) widget.badge!,
          if (widget.isHighlighted && gridMorph > 0.01)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: gridMorph.clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: widget.isCircle ? null : effectiveRadius,
                      shape: widget.isCircle
                          ? BoxShape.circle
                          : BoxShape.rectangle,
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      border: Border.all(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.isSelectionMode)
            Positioned.fill(
              child: Container(
                color: overlayColor,
              ),
            ),
          if (widget.isSelectionMode)
            Align(
              alignment: checkboxAlign,
              child: Padding(
                padding: checkboxPadding,
                child: SizedBox(
                  width: lerpDouble(32.0, 28.0, gridMorph)!,
                  height: lerpDouble(32.0, 28.0, gridMorph)!,
                  child: Checkbox(
                    value: widget.isSelected,
                    onChanged: (_) => widget.onToggleSelect?.call(),
                    fillColor: WidgetStateProperty.all(Colors.white),
                    checkColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          if (!widget.isSelectionMode && widget.onPlay != null)
            Positioned(
              right: lerpDouble(0.0, 8.0, gridMorph)!,
              bottom: lerpDouble(0.0, 8.0, gridMorph)!,
              child: IgnorePointer(
                ignoring: !(isGridTarget && _isHovered),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: isGridTarget && _isHovered ? 1.0 : 0.0,
                  child: CoverPlayButton(
                    size: 36,
                    iconSize: 22,
                    onTap: widget.onPlay!,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final clipped = widget.isCircle
        ? ClipOval(child: content)
        : ClipRRect(borderRadius: effectiveRadius, child: content);

    if (widget.onPlay != null) {
      return MouseRegion(
        onEnter: (_) {
          if (!_isHovered) setState(() => _isHovered = true);
        },
        onExit: (_) {
          if (_isHovered) setState(() => _isHovered = false);
        },
        child: clipped,
      );
    }

    return clipped;
  }
}
