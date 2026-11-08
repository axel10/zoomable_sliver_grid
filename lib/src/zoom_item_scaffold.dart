import 'dart:math' as math;
import 'dart:ui' show FontFeature, lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'zoom_item_cover.dart';
import 'zoom_layout_utils.dart';

/// 为单侧可见（原地淡入淡出）条目向子树下发锁定的稳态 [FolderZoomLayoutMetrics]。
class ZoomItemEffectiveMetrics extends InheritedWidget {
  const ZoomItemEffectiveMetrics({
    super.key,
    required this.metrics,
    required super.child,
  });

  final FolderZoomLayoutMetrics metrics;

  static FolderZoomLayoutMetrics? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ZoomItemEffectiveMetrics>()
        ?.metrics;
  }

  @override
  bool updateShouldNotify(ZoomItemEffectiveMetrics oldWidget) =>
      !identical(oldWidget.metrics, metrics);
}

/// Computed geometric layout for an item undergoing animated list-to-grid zoom morphing.
class ZoomItemLayout {
  final double coverLeft;
  final double coverTop;
  final double coverSize;
  final double textLeft;
  final double textTop;
  final double textWidth;
  final double textHeight;
  final double trailingSpace;
  final double listPadH;

  const ZoomItemLayout({
    required this.coverLeft,
    required this.coverTop,
    required this.coverSize,
    required this.textLeft,
    required this.textTop,
    required this.textWidth,
    required this.textHeight,
    required this.trailingSpace,
    required this.listPadH,
  });

  /// Computes the layout positions and dimensions for given constraints and zoom metrics.
  static ZoomItemLayout compute({
    required BoxConstraints constraints,
    required FolderZoomLayoutMetrics metrics,
    required bool isPortrait,
    double? trailingWidth,
    double selectionOffset = 0.0,
  }) {
    final gridMorph = metrics.gridMorph;
    final W = constraints.maxWidth;
    final H = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : metrics.animatedListExtent;

    final listPadH = isPortrait ? 12.0 : 16.0;
    final listCoverSize = getFolderListCoverSize(
      metrics.animatedZoomScale,
    ).clamp(0.0, math.max(0.0, H - 8.0));
    final listCoverLeft = listPadH;
    final listCoverTop = ((H - listCoverSize) / 2.0).clamp(0.0, H);

    final gridCoverSize = math.max(
      0.0,
      math.min(W, H - metrics.animatedGridTextHeight),
    );
    final gridCoverLeft = (W - gridCoverSize) / 2.0;
    const gridCoverTop = 0.0;

    final coverLeft = lerpDouble(listCoverLeft, gridCoverLeft, gridMorph)!;
    final coverTop = lerpDouble(listCoverTop, gridCoverTop, gridMorph)!;
    final coverSize = lerpDouble(listCoverSize, gridCoverSize, gridMorph)!;

    final trailingSpace = lerpDouble(trailingWidth ?? 0.0, 0.0, gridMorph)!;

    final coverProgress = (listCoverSize / 40.0).clamp(0.0, 1.0);
    final listCoverGap = 16.0 * coverProgress;

    final listTextLeft =
        listCoverLeft + listCoverSize + listCoverGap + selectionOffset;
    final listTextHeight = math.max(listCoverSize, math.max(0.0, H - 8.0));
    final listTextTop = ((H - listTextHeight) / 2.0).clamp(0.0, H);
    final listTextWidth = math.max(
      0.0,
      W - listTextLeft - listPadH - trailingSpace,
    );

    const gridTextLeft = 0.0;
    final gridTextTop = gridCoverSize + 8.0;
    final gridTextWidth = W;
    final gridTextHeight = math.max(0.0, H - gridTextTop);

    final textLeft = lerpDouble(listTextLeft, gridTextLeft, gridMorph)!;
    final textTop = lerpDouble(listTextTop, gridTextTop, gridMorph)!;
    final textWidth = lerpDouble(listTextWidth, gridTextWidth, gridMorph)!;
    final textHeight = lerpDouble(listTextHeight, gridTextHeight, gridMorph)!;

    return ZoomItemLayout(
      coverLeft: coverLeft,
      coverTop: coverTop,
      coverSize: coverSize,
      textLeft: textLeft,
      textTop: textTop,
      textWidth: textWidth,
      textHeight: textHeight,
      trailingSpace: trailingSpace,
      listPadH: listPadH,
    );
  }
}

/// Typography resolution helper for zoom items across list and grid tiers.
class ZoomItemTypography {
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;
  final TextStyle infoStyle;

  const ZoomItemTypography({
    required this.titleStyle,
    required this.subtitleStyle,
    this.infoStyle = const TextStyle(),
  });

  /// Resolves the default title, subtitle, and info text styles based on [FolderZoomLayoutMetrics].
  static ZoomItemTypography resolve({
    required BuildContext context,
    required FolderZoomLayoutMetrics metrics,
    Color? titleColor,
    Color? subtitleColor,
    Color? infoColor,
    FontWeight? listTitleFontWeight,
    double? listTitleFontSize,
  }) {
    final theme = Theme.of(context);
    final isPortrait = metrics.isPortrait;
    final isGridTarget = metrics.isGridTarget;

    final info = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontSize: metrics.animatedInfoFontSize,
      color: infoColor ??
          theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
      height: 1.2,
    );

    if (!isGridTarget) {
      final title = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
        color: titleColor ?? theme.colorScheme.onSurface,
        fontWeight: listTitleFontWeight ?? FontWeight.w600,
        fontSize: listTitleFontSize ?? metrics.animatedTitleFontSize,
        height: 1.2,
      );
      final subtitle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: metrics.animatedSubtitleFontSize,
        color: subtitleColor ?? theme.colorScheme.onSurfaceVariant,
        height: 1.2,
      );
      return ZoomItemTypography(
        titleStyle: title,
        subtitleStyle: subtitle,
        infoStyle: info,
      );
    } else {
      final title = ((isPortrait
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.titleMedium) ??
              const TextStyle())
          .copyWith(
        fontWeight: FontWeight.w600,
        fontSize: metrics.animatedTitleFontSize,
        color: titleColor ?? theme.colorScheme.onSurface,
        height: 1.25,
      );
      final subtitle =
          (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: metrics.animatedSubtitleFontSize,
        color: subtitleColor ?? theme.colorScheme.onSurfaceVariant,
        height: 1.2,
      );
      return ZoomItemTypography(
        titleStyle: title,
        subtitleStyle: subtitle,
        infoStyle: info,
      );
    }
  }
}

/// Standard 2-line text column widget for a zoom item.
class ZoomItemDefaultTextColumn extends StatelessWidget {
  final String title;
  final String? subtitle;
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;
  final double gridMorph;
  final Alignment alignment;
  final CrossAxisAlignment crossAxisAlignment;
  final Widget? titlePrefix;
  final Widget? titleSuffix;

  const ZoomItemDefaultTextColumn({
    super.key,
    required this.title,
    this.subtitle,
    required this.titleStyle,
    required this.subtitleStyle,
    required this.gridMorph,
    this.alignment = Alignment.centerLeft,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.titlePrefix,
    this.titleSuffix,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: OverflowBox(
        minHeight: 0.0,
        maxHeight: double.infinity,
        alignment: alignment,
        child: Column(
          crossAxisAlignment: crossAxisAlignment,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (titlePrefix != null) ...[
                  titlePrefix!,
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
                if (titleSuffix != null) ...[
                  const SizedBox(width: 4),
                  titleSuffix!,
                ],
              ],
            ),
            if (subtitle != null) ...[
              SizedBox(height: lerpDouble(4.0, 3.0, gridMorph)!),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: subtitleStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 3-line morphing text column.
class ZoomItemMorphingInfoColumn extends StatelessWidget {
  const ZoomItemMorphingInfoColumn({
    super.key,
    required this.metrics,
    required this.title,
    this.subtitle,
    required this.info,
    required this.titleStyle,
    required this.subtitleStyle,
    required this.infoStyle,
    required this.width,
    required this.height,
    this.titlePrefix,
    this.titleSuffix,
    this.gridAlignment = Alignment.topLeft,
    this.gridCrossAxisAlignment = CrossAxisAlignment.start,
  });

  final FolderZoomLayoutMetrics metrics;
  final String title;
  final String? subtitle;
  final String info;
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;
  final TextStyle infoStyle;
  final double width;
  final double height;
  final Widget? titlePrefix;
  final Widget? titleSuffix;
  final Alignment gridAlignment;
  final CrossAxisAlignment gridCrossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final effectiveMetrics =
        ZoomItemEffectiveMetrics.maybeOf(context) ?? metrics;
    final Widget content;
    if (effectiveMetrics.renderAsGrid) {
      content = ZoomItemDefaultTextColumn(
        title: title,
        subtitle: subtitle,
        titleStyle: titleStyle,
        subtitleStyle: subtitleStyle,
        gridMorph: effectiveMetrics.gridMorph,
        alignment: gridAlignment,
        crossAxisAlignment: gridCrossAxisAlignment,
        titlePrefix: titlePrefix,
        titleSuffix: titleSuffix,
      );
    } else {
      content = _buildListMorph(context, effectiveMetrics);
    }

    final reveal = effectiveMetrics.contentReveal;
    if (reveal >= 0.999) return content;
    return Opacity(opacity: reveal, child: content);
  }

  Widget _buildListMorph(
    BuildContext context,
    FolderZoomLayoutMetrics effectiveMetrics,
  ) {
    final W = width;
    final H = height;
    final compactMorph = effectiveMetrics.compactMorph;
    final t = (1.0 - compactMorph).clamp(0.0, 1.0);

    final titleLineHeight = effectiveMetrics.animatedTitleFontSize * 1.25;
    final subLineHeight = effectiveMetrics.animatedSubtitleFontSize * 1.2;
    final infoLineHeight = effectiveMetrics.animatedInfoFontSize * 1.2;

    final textPainter = TextPainter(
      text: TextSpan(
        text: info,
        style: infoStyle.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final measuredInfoWidth = (textPainter.width + 2.0).ceilToDouble();
    final compactInfoWidth =
        math.min(measuredInfoWidth, math.max(0.0, W * 0.45));
    final compactTitleWidth = math.max(0.0, W - compactInfoWidth - 12.0);

    const compactSubGap = 3.0;
    final compactBlockHeight = subtitle != null
        ? (titleLineHeight + compactSubGap + subLineHeight)
        : titleLineHeight;
    final compactTitleTop = ((H - compactBlockHeight) / 2.0).clamp(0.0, H);
    final compactInfoTop = ((H - infoLineHeight) / 2.0).clamp(0.0, H);
    final compactInfoLeft = math.max(0.0, W - compactInfoWidth);

    const standardGap = 2.0;
    final standardBlockHeight = subtitle != null
        ? (titleLineHeight +
            standardGap +
            subLineHeight +
            standardGap +
            infoLineHeight)
        : (titleLineHeight + standardGap + infoLineHeight);
    final standardTitleTop = ((H - standardBlockHeight) / 2.0).clamp(0.0, H);
    final standardSubTop = standardTitleTop + titleLineHeight + standardGap;
    final standardInfoTop = subtitle != null
        ? (standardSubTop + subLineHeight + standardGap)
        : (standardTitleTop + titleLineHeight + standardGap);

    final yt = math.pow(t, 0.5).toDouble();
    final xt = math.pow(t, 1.8).toDouble();

    final titleTop = lerpDouble(compactTitleTop, standardTitleTop, t)!;
    final titleWidth = lerpDouble(compactTitleWidth, W, yt)!;
    final subGap = lerpDouble(compactSubGap, standardGap, t)!;
    final subTop = titleTop + titleLineHeight + subGap;
    final subWidth = titleWidth;

    final infoTop = lerpDouble(compactInfoTop, standardInfoTop, yt)!;
    final infoLeft = lerpDouble(compactInfoLeft, 0.0, xt)!;
    final infoWidth = math.max(compactInfoWidth, W - infoLeft);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0.0,
          top: titleTop,
          width: titleWidth,
          height: titleLineHeight,
          child: Row(
            children: [
              if (titlePrefix != null) ...[
                titlePrefix!,
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              if (titleSuffix != null) ...[
                const SizedBox(width: 4),
                titleSuffix!,
              ],
            ],
          ),
        ),
        if (subtitle != null)
          Positioned(
            left: 0.0,
            top: subTop,
            width: subWidth,
            height: subLineHeight,
            child: Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtitleStyle,
            ),
          ),
        Positioned(
          left: infoLeft,
          top: infoTop,
          width: infoWidth,
          height: infoLineHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              info,
              style: infoStyle.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

/// Unified scaffold widget for all ZoomItem components.
class ZoomItemScaffold extends StatelessWidget {
  final FolderZoomLayoutMetrics metrics;
  final Widget? cover;
  final String? titleText;
  final String? subtitleText;
  final String? infoText;
  final Widget? textColumn;
  final Widget Function(BuildContext context, double textWidth, double textHeight)?
      textColumnBuilder;
  final Widget? trailing;
  final double? trailingWidth;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isHighlighted;
  final bool wrapHoverableCard;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(LongPressStartDetails details)? onLongPressStart;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final void Function(Offset position)? onContextMenu;
  final BorderRadius? borderRadius;
  final Color? titleColor;
  final Color? subtitleColor;
  final Color? infoColor;
  final FontWeight? listTitleFontWeight;
  final double? listTitleFontSize;
  final CrossAxisAlignment? gridCrossAxisAlignment;
  final Alignment? gridAlignment;
  final double selectionOffset;
  final Widget? fallbackLeadingWhenNoCover;
  final Widget? titlePrefix;
  final Widget? titleSuffix;

  /// 本条目在 Sliver 列表/网格中的索引（即 `SliverChildBuilderDelegate(context, index)` 的 index）。
  ///
  /// 若显式传入，内部直接使用该索引计算过渡状态，彻底省去每帧 Layout 阶段沿
  /// RenderObject 树向上递归回溯的开销；留空时自动回退为 [_findSliverChildIndex]。
  final int? index;

  /// 本条目所属的网格段，必须与 [SliverAnimatedZoomGridDelegate.section] 一致。
  ///
  /// 一页多个网格时，各段的条目索引都从 0 开始，只有把段带上才能取到自己的
  /// 淡入 / 淡出分类。单列表用法留空即可。
  final Object? section;

  const ZoomItemScaffold({
    super.key,
    required this.metrics,
    this.index,
    this.section,
    this.cover,
    this.titleText,
    this.subtitleText,
    this.infoText,
    this.textColumn,
    this.textColumnBuilder,
    this.trailing,
    this.trailingWidth,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isHighlighted = false,
    this.wrapHoverableCard = true,
    this.onTap,
    this.onLongPress,
    this.onLongPressStart,
    this.onSecondaryTapDown,
    this.onContextMenu,
    this.borderRadius,
    this.titleColor,
    this.subtitleColor,
    this.infoColor,
    this.listTitleFontWeight,
    this.listTitleFontSize,
    this.gridCrossAxisAlignment,
    this.gridAlignment,
    this.selectionOffset = 0.0,
    this.fallbackLeadingWhenNoCover,
    this.titlePrefix,
    this.titleSuffix,
  });

  static int? _findSliverChildIndex(BuildContext context) {
    RenderObject? current = context.findRenderObject();
    while (current != null) {
      final parentData = current.parentData;
      if (parentData is SliverMultiBoxAdaptorParentData) {
        return parentData.index;
      }
      current = current.parent;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final childIndex = index ?? _findSliverChildIndex(context);
        final transition = childIndex != null
            ? metrics.resolveItemTransition(childIndex, section: section)
            : null;
        final effectiveMetrics = transition?.effectiveMetrics ?? metrics;
        final isFadeScale = transition != null && !transition.isShared;

        final theme = Theme.of(context);
        final isPortrait = effectiveMetrics.isPortrait;
        final gridMorph = effectiveMetrics.gridMorph;
        final isGridTarget = effectiveMetrics.isGridTarget;

        final coverRadiusValue = lerpDouble(8.0, 14.0, gridMorph)!;
        final effectiveRadius =
            borderRadius ?? BorderRadius.circular(coverRadiusValue);

        final typography = ZoomItemTypography.resolve(
          context: context,
          metrics: effectiveMetrics,
          titleColor: titleColor,
          subtitleColor: subtitleColor,
          infoColor: infoColor,
          listTitleFontWeight: listTitleFontWeight,
          listTitleFontSize: listTitleFontSize,
        );

        final defaultGridAlignment = gridAlignment ?? Alignment.topLeft;
        final textAlignAlignment = Alignment.lerp(
          Alignment.centerLeft,
          defaultGridAlignment,
          gridMorph,
        )!;
        final textCrossAlign = gridCrossAxisAlignment != null
            ? (gridMorph > 0.5
                ? gridCrossAxisAlignment!
                : CrossAxisAlignment.start)
            : CrossAxisAlignment.start;

        final effectiveSecondaryTapDown = onSecondaryTapDown ??
            (onContextMenu != null
                ? (details) => onContextMenu!(details.globalPosition)
                : null);
        final effectiveLongPressStart = onLongPressStart ??
            (onContextMenu != null
                ? (details) => onContextMenu!(details.globalPosition)
                : null);
        final effectiveLongPress = onLongPress ??
            (onContextMenu != null ? () => onContextMenu!(Offset.zero) : null);

        final listBgAlpha = (1.0 - gridMorph).clamp(0.0, 1.0);
        final Color itemBgColor;
        if (isSelectionMode && isSelected && listBgAlpha > 0.01) {
          itemBgColor = theme.colorScheme.primaryContainer
              .withValues(alpha: 0.35 * listBgAlpha);
        } else if (isHighlighted && listBgAlpha > 0.01) {
          itemBgColor =
              theme.colorScheme.primary.withValues(alpha: 0.2 * listBgAlpha);
        } else {
          itemBgColor = Colors.transparent;
        }

        final effectiveSelectionOffset = isFadeScale
            ? ((isSelectionMode && gridMorph < 0.5)
                ? (28.0 *
                    (1.0 -
                        (getFolderListCoverSize(
                                  effectiveMetrics.animatedZoomScale,
                                ) /
                                40.0)
                            .clamp(0.0, 1.0)))
                : 0.0)
            : selectionOffset;

        final layout = ZoomItemLayout.compute(
          constraints: constraints,
          metrics: effectiveMetrics,
          isPortrait: isPortrait,
          trailingWidth: trailingWidth,
          selectionOffset: effectiveSelectionOffset,
        );

        Widget buildDefaultColumn() {
          if (textColumn != null) return textColumn!;
          if (titleText == null) return const SizedBox.shrink();
          if (infoText != null) {
            return ZoomItemMorphingInfoColumn(
              metrics: effectiveMetrics,
              title: titleText!,
              subtitle: subtitleText,
              info: infoText!,
              titleStyle: typography.titleStyle,
              subtitleStyle: typography.subtitleStyle,
              infoStyle: typography.infoStyle,
              width: layout.textWidth,
              height: layout.textHeight,
              titlePrefix: titlePrefix,
              titleSuffix: titleSuffix,
              gridAlignment: defaultGridAlignment,
              gridCrossAxisAlignment:
                  gridCrossAxisAlignment ?? CrossAxisAlignment.start,
            );
          }
          return ZoomItemDefaultTextColumn(
            title: titleText!,
            subtitle: subtitleText,
            titleStyle: typography.titleStyle,
            subtitleStyle: typography.subtitleStyle,
            gridMorph: gridMorph,
            alignment: textAlignAlignment,
            crossAxisAlignment: textCrossAlign,
            titlePrefix: titlePrefix,
            titleSuffix: titleSuffix,
          );
        }

        final itemContent = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: effectiveSecondaryTapDown,
          onLongPressStart: effectiveLongPressStart,
          onLongPress: effectiveLongPress,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: itemBgColor,
              borderRadius: effectiveRadius,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: effectiveRadius,
              child: InkWell(
                borderRadius: effectiveRadius,
                enableFeedback: false,
                onTap: onTap,
                hoverColor: gridMorph < 0.5
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
                    : Colors.transparent,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (layout.coverSize > 0.5 && cover != null)
                      Positioned(
                        left: layout.coverLeft,
                        top: layout.coverTop,
                        width: layout.coverSize,
                        height: layout.coverSize,
                        child: cover!,
                      )
                    else if (fallbackLeadingWhenNoCover != null &&
                        gridMorph < 0.5)
                      Positioned(
                        left: layout.coverLeft,
                        top: ((constraints.maxHeight.isFinite
                                        ? constraints.maxHeight
                                        : effectiveMetrics.animatedListExtent) -
                                    24.0) /
                                2.0,
                        width: 24.0,
                        height: 24.0,
                        child: fallbackLeadingWhenNoCover!,
                      ),
                    Positioned(
                      left: layout.textLeft,
                      top: layout.textTop,
                      width: layout.textWidth,
                      height: layout.textHeight,
                      child: textColumnBuilder != null
                          ? textColumnBuilder!(
                              context,
                              layout.textWidth,
                              layout.textHeight,
                            )
                          : buildDefaultColumn(),
                    ),
                    if (gridMorph < 0.99 && trailing != null)
                      Positioned(
                        right: layout.listPadH,
                        top: 0,
                        bottom: 0,
                        child: Opacity(
                          opacity: (1.0 - gridMorph).clamp(0.0, 1.0),
                          child: Center(child: trailing),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );

        Widget result = wrapHoverableCard
            ? HoverableCard(
                enabled: isGridTarget,
                child: itemContent,
              )
            : itemContent;

        // 这三层包装必须**常驻**，不能在过渡开始 / 结束时按条件增删。
        //
        // 它们一增删，`LayoutBuilder` 之下的根 Widget 类型就变了，Flutter 无法复用
        // 旧 Element，只能把整条子树 deactivate 重建 —— 条目内部的 `SongThumbnail`
        // 等有状态组件会丢掉 State。单侧可见条目正好在过渡**收尾**那一帧从
        // `Opacity > Transform > ZoomItemEffectiveMetrics > HoverableCard`
        // 塌缩成 `HoverableCard`，于是刚淡入完的封面被销毁重建：
        // 有封面的条目靠 ImageCache 同步出图、看不出来，而落定为默认图标的条目
        // `_isGenerating` 回到 true，会先空白一两帧再重新解析出来（观感就是
        // 「淡入结束之后默认图标闪一下」）。
        // 代价只有两个 render object：`Opacity` 在 1.0 时直接透传不建图层，
        // `Transform` 在单位矩阵下只是一次 canvas 变换。
        final double itemOpacity =
            isFadeScale ? transition.opacity.clamp(0.0, 1.0) : 1.0;
        final double itemScale = isFadeScale ? transition.scale : 1.0;
        result = Opacity(
          opacity: itemOpacity,
          child: Transform.scale(
            scale: itemScale,
            alignment: Alignment.center,
            child: ZoomItemEffectiveMetrics(
              metrics: effectiveMetrics,
              child: result,
            ),
          ),
        );

        return result;
      },
    );
  }
}
