import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'zoom_pinch.dart';

/// 网格视图的标准横向（列）间距
const double kGridCrossAxisSpacing = 16.0;

/// 网格视图的标准纵向（行）间距
const double kGridMainAxisSpacing = 24.0;

/// 网格视图的标准左右内边距
const double kGridHorizontalPadding = 16.0;

/// Discrete fixed tier values for `folderZoomScale`:
/// List view (4 tiers): 0.0, 1/6, 2/6, 3/6
/// Grid view (3 tiers): 4/6, 5/6, 1.0
const double kFolderZoomTierMinimalList = 0.0;
const double kFolderZoomTierCompactList = 1.0 / 6.0;
const double kFolderZoomTierStandardList = 2.0 / 6.0;
const double kFolderZoomTierLargeList = 3.0 / 6.0;
const double kFolderZoomTierSmallGrid = 4.0 / 6.0;
const double kFolderZoomTierMediumGrid = 5.0 / 6.0;
const double kFolderZoomTierLargeGrid = 1.0;

const List<double> kFolderZoomTierValues = [
  kFolderZoomTierMinimalList,
  kFolderZoomTierCompactList,
  kFolderZoomTierStandardList,
  kFolderZoomTierLargeList,
  kFolderZoomTierSmallGrid,
  kFolderZoomTierMediumGrid,
  kFolderZoomTierLargeGrid,
];

/// Snaps an arbitrary zoom scale to the closest discrete tier value.
double snapFolderZoomScale(double value) {
  double closest = kFolderZoomTierValues.first;
  double minDiff = (value - closest).abs();
  for (final v in kFolderZoomTierValues) {
    final diff = (value - v).abs();
    if (diff < minDiff) {
      minDiff = diff;
      closest = v;
    }
  }
  return closest;
}

/// Steps the zoom scale up or down by [delta] tiers.
double stepFolderZoomScale(double current, int delta) {
  final currentSnapped = snapFolderZoomScale(current);
  final index = kFolderZoomTierValues.indexOf(currentSnapped);
  if (index == -1) return currentSnapped;
  final newIndex = (index + delta).clamp(0, kFolderZoomTierValues.length - 1);
  return kFolderZoomTierValues[newIndex];
}

/// Discrete layout & typography tiers derived from `folderZoomScale`.
enum FolderZoomTier {
  /// Tier 0: Single-column minimal list without cover/thumbnail (pure text).
  minimalList,

  /// Tier 1: Single-column compact list with smaller cover; song info on the right.
  compactList,

  /// Tier 2: Single-column standard list with medium cover; 3-line column.
  standardList,

  /// Tier 3: Single-column spacious list with large cover; 3-line column.
  largeList,

  /// Tier 4: Multi-column compact grid with higher column density.
  smallGrid,

  /// Tier 5: Multi-column standard grid.
  mediumGrid,

  /// Tier 6: Multi-column spacious grid with lower column density and larger cards.
  largeGrid,
}

typedef ZoomTier = FolderZoomTier;

extension FolderZoomTierX on FolderZoomTier {
  /// Whether this tier represents a grid view.
  bool get isGrid => switch (this) {
        FolderZoomTier.minimalList ||
        FolderZoomTier.compactList ||
        FolderZoomTier.standardList ||
        FolderZoomTier.largeList =>
          false,
        FolderZoomTier.smallGrid ||
        FolderZoomTier.mediumGrid ||
        FolderZoomTier.largeGrid =>
          true,
      };

  /// Discrete cover size in list view (0.0 for minimal list with thumbnail hidden).
  double get listCoverSize => switch (this) {
        FolderZoomTier.minimalList => 0.0,
        FolderZoomTier.compactList => 40.0,
        FolderZoomTier.standardList => 64.0,
        FolderZoomTier.largeList => 88.0,
        _ => 0.0,
      };

  /// Discrete single-row tile extent (height) in list view.
  double get listTileExtent => switch (this) {
        FolderZoomTier.minimalList => 48.0,
        FolderZoomTier.compactList => 56.0,
        FolderZoomTier.standardList => 80.0,
        FolderZoomTier.largeList => 104.0,
        _ => 56.0,
      };

  /// Normalized zoom scale for this discrete tier.
  double get zoomScale => kFolderZoomTierValues[index];
}

FolderZoomTier getFolderZoomTier(double zoomScale) {
  final snapped = snapFolderZoomScale(zoomScale);
  int bestIdx = 0;
  double minDiff = double.infinity;
  for (int i = 0; i < kFolderZoomTierValues.length; i++) {
    final diff = (snapped - kFolderZoomTierValues[i]).abs();
    if (diff < minDiff) {
      minDiff = diff;
      bestIdx = i;
    }
  }
  return FolderZoomTier.values[bestIdx];
}

/// Boundary threshold between list tiers and grid tiers.
const double kFolderZoomGridThreshold =
    (kFolderZoomTierLargeList + kFolderZoomTierSmallGrid) / 2.0;

bool isFolderZoomGrid(double zoomScale) => zoomScale >= kFolderZoomGridThreshold;

/// Both Minimal List and Compact List use the 2-line right-aligned info layout.
bool isFolderZoomCompactList(double zoomScale) =>
    zoomScale < (kFolderZoomTierCompactList + kFolderZoomTierStandardList) / 2.0;

/// Piecewise linear interpolation across list tiers for a layout property.
double _interpolateListTierProperty(
  double zoomScale,
  double Function(FolderZoomTier tier) propertyGetter,
) {
  const listTiers = [
    FolderZoomTier.minimalList,
    FolderZoomTier.compactList,
    FolderZoomTier.standardList,
    FolderZoomTier.largeList,
  ];

  if (zoomScale <= listTiers.first.zoomScale) {
    return propertyGetter(listTiers.first);
  }
  if (zoomScale >= listTiers.last.zoomScale) {
    return propertyGetter(listTiers.last);
  }

  for (int i = 0; i < listTiers.length - 1; i++) {
    final t0 = listTiers[i];
    final t1 = listTiers[i + 1];
    if (zoomScale >= t0.zoomScale && zoomScale <= t1.zoomScale) {
      final span = t1.zoomScale - t0.zoomScale;
      final fraction = span <= 0.0 ? 0.0 : (zoomScale - t0.zoomScale) / span;
      return lerpDouble(propertyGetter(t0), propertyGetter(t1), fraction)!;
    }
  }
  return propertyGetter(listTiers.last);
}

/// Thumbnail size in list view (`zoomScale < kFolderZoomGridThreshold`),
/// ranging smoothly from `0px` (minimal list, hidden) to `88px` (large list).
double getFolderListCoverSize(double zoomScale) {
  return _interpolateListTierProperty(zoomScale, (t) => t.listCoverSize);
}

/// Total height of a single row tile in list view,
/// ranging from `48px` (minimal list) to `104px` (large list).
double getFolderListTileExtent(double zoomScale) {
  return _interpolateListTierProperty(zoomScale, (t) => t.listTileExtent);
}

/// Returns the discrete text block height below the cover in grid view.
///
/// Text size changes by tier (`smallGrid`, `mediumGrid`, `largeGrid`) rather
/// than scaling continuously with `zoomScale`.
double calculateFolderZoomGridTextHeight(
  BuildContext context, {
  required double zoomScale,
}) {
  return folderZoomGridTextHeightFor(
    tier: getFolderZoomTier(zoomScale),
    isPortrait: MediaQuery.of(context).orientation == Orientation.portrait,
    textScale: folderZoomTextScaleOf(context),
  );
}

/// [calculateFolderZoomGridTextHeight] 的纯函数版本：不碰 `MediaQuery`。
double folderZoomGridTextHeightFor({
  required FolderZoomTier tier,
  required bool isPortrait,
  required double textScale,
}) {
  final clampedScale = textScale.clamp(1.0, 1.3);
  final double baseHeight = switch (tier) {
    FolderZoomTier.smallGrid => isPortrait ? 58.0 : 62.0,
    FolderZoomTier.mediumGrid => isPortrait ? 64.0 : 68.0,
    FolderZoomTier.largeGrid || _ => isPortrait ? 70.0 : 74.0,
  };
  return baseHeight * clampedScale;
}

/// 系统文字缩放系数（以 `10pt` 为基准），统一走这一个入口。
double folderZoomTextScaleOf(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) / 10;

/// 插值字号的对齐步长。
const double kFolderZoomFontSizeQuantum = 0.5;

/// 把插值出来的字号对齐到 [kFolderZoomFontSizeQuantum]。
double quantizeFolderZoomFontSize(double fontSize) =>
    (fontSize / kFolderZoomFontSizeQuantum).roundToDouble() *
    kFolderZoomFontSizeQuantum;

/// 网格条目的字号三元组：（标题、副标题、第三行信息）。
typedef FolderGridFontSizes = ({double title, double subtitle, double info});

/// 根据档位、卡片宽度及屏幕方向，解析出该档位的基准字号三元组（标题、副标题、第三行信息）。
FolderGridFontSizes resolveFolderZoomFontSizes({
  required FolderZoomTier tier,
  required double cardWidth,
  required bool isPortrait,
}) {
  final gridFonts = folderGridFontSizes(cardWidth);
  return switch (tier) {
    FolderZoomTier.minimalList => isPortrait
        ? (title: 13.5, subtitle: 11.5, info: 11.0)
        : (title: 14.0, subtitle: 12.0, info: 12.0),
    FolderZoomTier.compactList => isPortrait
        ? (title: 14.0, subtitle: 12.0, info: 11.0)
        : (title: 14.5, subtitle: 12.5, info: 12.0),
    FolderZoomTier.standardList => isPortrait
        ? (title: 14.0, subtitle: 12.0, info: 11.0)
        : (title: 15.5, subtitle: 13.0, info: 13.0),
    FolderZoomTier.largeList => isPortrait
        ? (title: 15.5, subtitle: 13.0, info: 11.5)
        : (title: 16.5, subtitle: 13.5, info: 13.5),
    FolderZoomTier.smallGrid ||
    FolderZoomTier.mediumGrid ||
    FolderZoomTier.largeGrid =>
      gridFonts,
  };
}

/// 网格条目字号——按**卡片宽度**分档，而不是屏幕宽度。
FolderGridFontSizes folderGridFontSizes(double cardWidth) {
  if (cardWidth >= 240.0) {
    return (title: 15.0, subtitle: 12.5, info: 11.0);
  }
  if (cardWidth >= 200.0) {
    return (title: 14.5, subtitle: 12.0, info: 10.5);
  }
  if (cardWidth >= 150.0) {
    return (title: 13.5, subtitle: 11.5, info: 10.0);
  }
  if (cardWidth >= 110.0) {
    return (title: 12.5, subtitle: 10.5, info: 9.5);
  }
  return (title: 11.5, subtitle: 9.5, info: 9.0);
}

/// 列表视图的行间距（相邻两行 `Row` 之间）。
const double kFolderListRowSpacing = 0.0;

/// 内容区的左右内边距。
double folderContentHorizontalPadding({
  required bool isPortrait,
  required double gridMorph,
}) {
  return lerpDouble(
    isPortrait ? 4.0 : 8.0,
    kGridHorizontalPadding,
    gridMorph.clamp(0.0, 1.0),
  )!;
}

/// 缩放的布局规格：列数、卡片几何、滚动偏移估算。
class FolderZoomPolicy {
  /// 网格卡片宽度（内容宽度下均分）。
  final double cardWidth;

  /// 网格卡片总高（封面 + 文字区）。
  final double cardHeight;

  /// 列表视图的单行步距（行高 + [kFolderListRowSpacing]）。
  final double listRowStride;

  /// 网格列数。
  final int crossAxisCount;

  /// 目标档位是否落在网格侧（`zoomScale >= 0.5`）。
  final bool isGrid;

  const FolderZoomPolicy._({
    required this.cardWidth,
    required this.cardHeight,
    required this.listRowStride,
    required this.crossAxisCount,
    required this.isGrid,
  });

  /// 标准网格 delegate（如排序态 `SliverGridDelegateWithFixedCrossAxisCount`）的宽高比。
  double get childAspectRatio =>
      (cardWidth > 0 && cardHeight > 0) ? cardWidth / cardHeight : 1.0;

  /// 由上下文、外层宽度与缩放档位解析出完整布局规格。
  factory FolderZoomPolicy.resolve({
    required BuildContext context,
    required double outerWidth,
    required double zoomScale,
    bool? isPortrait,
  }) {
    final snappedZoom = snapFolderZoomScale(zoomScale);
    final portrait = isPortrait ??
        (MediaQuery.maybeOrientationOf(context) == Orientation.portrait);
    final tier = getFolderZoomTier(snappedZoom);
    final isGrid = isFolderZoomGrid(snappedZoom);

    final crossAxisCount = calculateCrossAxisCount(
      width: outerWidth,
      tier: tier,
      isPortrait: portrait,
    );
    final horizontalPadding = folderContentHorizontalPadding(
      isPortrait: portrait,
      gridMorph: isGrid ? 1.0 : 0.0,
    );
    final contentWidth = math.max(
      1.0,
      outerWidth - horizontalPadding * 2,
    );
    final cardWidth = gridCardWidth(
      contentWidth: contentWidth,
      crossAxisCount: crossAxisCount,
    );
    final cardHeight = cardWidth +
        calculateFolderZoomGridTextHeight(context, zoomScale: snappedZoom);

    return FolderZoomPolicy._(
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      listRowStride:
          getFolderListTileExtent(snappedZoom) + kFolderListRowSpacing,
      crossAxisCount: crossAxisCount,
      isGrid: isGrid,
    );
  }

  /// 内容宽度下按 [crossAxisCount] 均分得到的卡片宽度。
  static double gridCardWidth({
    required double contentWidth,
    required int crossAxisCount,
    double crossAxisSpacing = kGridCrossAxisSpacing,
  }) {
    if (crossAxisCount <= 0) return 0.0;
    final usable = contentWidth - (crossAxisCount - 1) * crossAxisSpacing;
    return math.max(1.0, usable / crossAxisCount);
  }

  /// Calculates responsive cross axis count based on [width], [tier], and [isPortrait].
  static int calculateCrossAxisCount({
    required double width,
    required FolderZoomTier tier,
    required bool isPortrait,
  }) {
    if (!isPortrait) {
      const baseLarge = 6;
      return switch (tier) {
        FolderZoomTier.smallGrid => baseLarge + 2, // 8
        FolderZoomTier.mediumGrid => baseLarge + 1, // 7
        FolderZoomTier.largeGrid || _ => baseLarge, // 6
      };
    }

    final baseLarge = switch (width) {
      >= 900 => 4,
      >= 600 => 3,
      _ => 2,
    };
    return switch (tier) {
      FolderZoomTier.smallGrid => baseLarge + 2,
      FolderZoomTier.mediumGrid => baseLarge + 1,
      FolderZoomTier.largeGrid || _ => baseLarge,
    };
  }

  /// Calculates scroll offset for an item at [songIndex] preceded by [folderCount] subfolders.
  double calculateScrollOffset({
    required int folderCount,
    required int songIndex,
  }) {
    double offset = 0.0;
    if (isGrid) {
      final folderRows = (folderCount / crossAxisCount).ceil();
      offset += folderRows * (cardHeight + kGridMainAxisSpacing);
      final songRows = (songIndex / crossAxisCount).floor();
      offset += songRows * (cardHeight + kGridMainAxisSpacing);
    } else {
      offset += folderCount * listRowStride;
      offset += songIndex * listRowStride;
    }
    return offset;
  }

  /// Centers the item offset within the viewport, clamped to maxScrollExtent.
  double centerInViewport({
    required double itemOffset,
    required double viewportDimension,
    required double maxScrollExtent,
  }) {
    final itemExtent = isGrid ? cardHeight : listRowStride;
    final target = itemOffset - (viewportDimension / 2) + (itemExtent / 2);
    return target.clamp(0.0, maxScrollExtent);
  }
}

typedef ZoomPolicy = FolderZoomPolicy;

/// 几何插值的**一端**：某个确定档位的稳态布局。
@immutable
class FolderZoomGeometryLayer {
  const FolderZoomGeometryLayer({
    required this.isGrid,
    required this.crossAxisCount,
    required this.gridTextHeight,
    required this.listExtent,
    required this.weight,
  });

  /// 该端是否走网格那套几何；false 时按列表整行算。
  final bool isGrid;

  /// 网格列数（整数）。
  final int crossAxisCount;

  /// 网格封面下方文字区高度（[isGrid] 为 false 时无意义）。
  final double gridTextHeight;

  /// 列表整行高度（[isGrid] 为 true 时无意义）。
  final double listExtent;

  /// 该端在本次插值中的权重，同一批 layer 的权重之和为 `1`。
  final double weight;

  @override
  bool operator ==(Object other) =>
      other is FolderZoomGeometryLayer &&
      other.isGrid == isGrid &&
      other.crossAxisCount == crossAxisCount &&
      other.gridTextHeight == gridTextHeight &&
      other.listExtent == listExtent &&
      other.weight == weight;

  @override
  int get hashCode => Object.hash(
        isGrid,
        crossAxisCount,
        gridTextHeight,
        listExtent,
        weight,
      );
}

/// 单侧可见条目在淡入淡出时的缩放幅度（`0.15` 对应 `0.85 <-> 1.0` 与 `1.0 <-> 1.15`）。
const double kFolderZoomFadeScaleDelta = 0.15;

/// 记录 Sliver 最近一次稳态视口范围与锚定条目，供档位过渡期间判定条目在起止档位的可见性及滚动锚定。
class FolderZoomViewportTracker {
  double usableWidth = 0.0;
  double outerWidth = 0.0;
  double viewportTop = 0.0;
  double viewportBottom = 0.0;
  double remainingPaintExtent = 0.0;
  bool hasMeasurement = false;

  /// 视口顶部的锚定条目索引。
  int anchorIndex = 0;

  /// 锚定条目顶部相对于视口顶部的偏移量（`geom.scrollOffset - viewportTop`）。
  double anchorOffsetInViewport = 0.0;

  /// 视口高度。
  double get viewportHeight => math.max(0.0, viewportBottom - viewportTop);

  /// 当前 Sliver 是否在视口中可见（用于多 Sliver 时仅激活可见 Sliver 的滚动吸附）。
  bool get isActiveInViewport => hasMeasurement && remainingPaintExtent > 10.0;

  void record({
    required double usableWidth,
    required double outerWidth,
    required double viewportTop,
    required double viewportBottom,
    required bool isAnimating,
    double remainingPaintExtent = 0.0,
    FolderZoomGeometryLayer? steadyLayer,
    bool isPortrait = false,
  }) {
    if (!hasMeasurement ||
        !isAnimating ||
        (this.outerWidth - outerWidth).abs() > 1.0) {
      this.usableWidth = usableWidth;
      this.outerWidth = outerWidth;
      this.viewportTop = viewportTop;
      this.viewportBottom = viewportBottom;
      this.remainingPaintExtent = remainingPaintExtent;
      hasMeasurement = true;

      if (steadyLayer != null) {
        if (viewportTop <= 0.0) {
          anchorIndex = 0;
          anchorOffsetInViewport = 0.0;
        } else {
          anchorIndex = _SliverAnimatedZoomGridLayout.minChildIndexIn(
            layer: steadyLayer,
            scrollOffset: viewportTop,
            usableWidth: usableWidth,
            outerWidth: outerWidth,
            isPortrait: isPortrait,
          );
          final geom = _SliverAnimatedZoomGridLayout.geometryInLayer(
            layer: steadyLayer,
            index: anchorIndex,
            usableWidth: usableWidth,
            outerWidth: outerWidth,
            isPortrait: isPortrait,
          );
          anchorOffsetInViewport = geom.scrollOffset - viewportTop;
        }
      }
    }
  }

  /// 获取指定档位 [layer] 对应锚定条目的视口顶部偏移。
  double viewportTopForLayer(
    FolderZoomGeometryLayer layer, {
    required double usableWidth,
    double outerWidth = 0.0,
    bool isPortrait = false,
  }) {
    if (viewportTop <= 0.0 || !hasMeasurement) return 0.0;
    final geom = _SliverAnimatedZoomGridLayout.geometryInLayer(
      layer: layer,
      index: anchorIndex,
      usableWidth: usableWidth,
      outerWidth: outerWidth,
      isPortrait: isPortrait,
    );
    return math.max(0.0, geom.scrollOffset - anchorOffsetInViewport);
  }
}

/// 单个条目在档位切换过渡期间的呈现方式。
@immutable
class FolderZoomItemTransition {
  const FolderZoomItemTransition({
    required this.isShared,
    required this.opacity,
    required this.scale,
    required this.effectiveMetrics,
  });

  /// 是否在起止两个档位都可见（true 时走位移动画，false 时原地淡入淡出+缩放）。
  final bool isShared;

  /// 条目整体不透明度（[isShared] 为 true 时恒为 `1.0`）。
  final double opacity;

  /// 条目整体缩放比例（[isShared] 为 true 时恒为 `1.0`）。
  final double scale;

  /// 条目内部排版使用的度量（单侧可见条目锁定在各自所属档位的稳态度量）。
  final FolderZoomLayoutMetrics effectiveMetrics;
}

/// Snapshot of animated layout metrics passed to unified folder/song slivers and items.
class FolderZoomLayoutMetrics {
  final double targetZoomScale;
  final double animatedZoomScale;

  /// `0.0` = pure 1-column List View, `1.0` = pure N-column Grid View.
  final double gridMorph;

  /// `0.0` = standard 3-line list item (song info below subtitle),
  /// `1.0` = compact 2-line list item (song info on the right side).
  final double compactMorph;

  /// Animated column count in Grid View (e.g. `4.0` -> `3.0`).
  final double animatedGridCols;

  /// Animated text block height below the cover in Grid View.
  final double animatedGridTextHeight;

  /// Animated row height in List View.
  final double animatedListExtent;

  /// 目标网格卡片宽度（**不参与动画**）。
  final double targetCardWidth;

  /// 平滑插值的标题字号。
  final double animatedTitleFontSize;

  /// 平滑插值的副标题字号。
  final double animatedSubtitleFontSize;

  /// 平滑插值的第三行（详细信息）字号。
  final double animatedInfoFontSize;

  /// 当前是否竖屏。
  final bool isPortrait;

  /// 条目内容该渲染网格那套还是列表那套。
  final bool? contentIsGrid;

  /// 内容交接时的整体不透明度（`1.0` = 完全清晰）。
  final double contentReveal;

  /// 条目几何的加权层，权重之和为 `1`，由 [FolderZoomSliverBuilder] 逐帧算好。
  final List<FolderZoomGeometryLayer> geometryLayers;

  /// 外层容器宽度（尚未扣除 [folderContentHorizontalPadding]）。
  final double outerWidth;

  /// 本轮档位变化的缩放差值（`toZoomScale - fromZoomScale`）。
  final double zoomScaleDelta;

  /// 起始档位的稳态度量。
  final FolderZoomLayoutMetrics? startEndpointMetrics;

  /// 目标档位的稳态度量。
  final FolderZoomLayoutMetrics? targetEndpointMetrics;

  /// 视口范围追踪器。
  final FolderZoomViewportTracker? viewportTracker;

  const FolderZoomLayoutMetrics({
    required this.targetZoomScale,
    required this.animatedZoomScale,
    required this.gridMorph,
    required this.compactMorph,
    required this.animatedGridCols,
    required this.animatedGridTextHeight,
    required this.animatedListExtent,
    required this.targetCardWidth,
    this.animatedTitleFontSize = 14.0,
    this.animatedSubtitleFontSize = 12.0,
    this.animatedInfoFontSize = 11.0,
    this.isPortrait = false,
    this.outerWidth = 0.0,
    this.contentIsGrid,
    this.contentReveal = 1.0,
    this.geometryLayers = const <FolderZoomGeometryLayer>[],
    this.zoomScaleDelta = 0.0,
    this.startEndpointMetrics,
    this.targetEndpointMetrics,
    this.viewportTracker,
  });

  /// 解析指定 [index] 在当前帧的过渡状态（双端可见走位移，单端可见走原地淡入淡出+缩放）。
  FolderZoomItemTransition resolveItemTransition(int index) {
    final layers = resolvedGeometryLayers;
    final tracker = viewportTracker;
    if (layers.length <= 1 || tracker == null || !tracker.hasMeasurement) {
      return FolderZoomItemTransition(
        isShared: true,
        opacity: 1.0,
        scale: 1.0,
        effectiveMetrics: this,
      );
    }

    final usableWidth = tracker.usableWidth;
    final effOuterWidth = outerWidth > 0.0 ? outerWidth : tracker.outerWidth;

    int visibleCount = 0;
    double visibleWeight = 0.0;
    bool visibleInTarget = false;

    for (var i = 0; i < layers.length; i++) {
      final layer = layers[i];
      final geom = _SliverAnimatedZoomGridLayout.geometryInLayer(
        layer: layer,
        index: index,
        usableWidth: usableWidth,
        outerWidth: effOuterWidth,
        isPortrait: isPortrait,
      );
      final layerViewTop = tracker.viewportTopForLayer(
        layer,
        usableWidth: usableWidth,
        outerWidth: effOuterWidth,
        isPortrait: isPortrait,
      );
      final layerViewBottom = layerViewTop + tracker.viewportHeight;
      final isVisible = _SliverAnimatedZoomGridLayout.isGeometryVisibleInViewport(
        geom,
        layerViewTop,
        layerViewBottom,
      );
      if (isVisible) {
        visibleCount++;
        visibleWeight += layer.weight;
        if (i == layers.length - 1) {
          visibleInTarget = true;
        }
      }
    }

    if (visibleCount == layers.length) {
      return FolderZoomItemTransition(
        isShared: true,
        opacity: 1.0,
        scale: 1.0,
        effectiveMetrics: this,
      );
    }

    if (visibleCount == 0) {
      return FolderZoomItemTransition(
        isShared: false,
        opacity: 0.0,
        scale: 1.0,
        effectiveMetrics: targetEndpointMetrics ?? this,
      );
    }

    final double opacity = visibleWeight.clamp(0.0, 1.0);
    final bool isGrowing = zoomScaleDelta >= 0.0;
    final double direction = (isGrowing == visibleInTarget) ? -1.0 : 1.0;
    final double scale =
        1.0 + direction * kFolderZoomFadeScaleDelta * (1.0 - opacity);
    final effective = visibleInTarget
        ? (targetEndpointMetrics ?? this)
        : (startEndpointMetrics ?? this);

    return FolderZoomItemTransition(
      isShared: false,
      opacity: opacity,
      scale: scale,
      effectiveMetrics: effective,
    );
  }

  /// 布局实际使用的加权层；[geometryLayers] 为空时按插值标量合成单层。
  List<FolderZoomGeometryLayer> get resolvedGeometryLayers {
    if (geometryLayers.isNotEmpty) return geometryLayers;
    return <FolderZoomGeometryLayer>[
      FolderZoomGeometryLayer(
        isGrid: gridMorph >= 0.5,
        crossAxisCount: animatedGridCols.round().clamp(1, 12),
        gridTextHeight: animatedGridTextHeight,
        listExtent: animatedListExtent,
        weight: 1.0,
      ),
    ];
  }

  bool get isGridTarget => isFolderZoomGrid(targetZoomScale);

  /// 条目内容实际使用的布局侧，见 [contentIsGrid]。
  bool get renderAsGrid => contentIsGrid ?? (gridMorph >= 0.5);

  FolderZoomTier get tier => getFolderZoomTier(targetZoomScale);

  /// Target discrete column count in Grid View (e.g. 6, 7, 8).
  int get targetGridCols => animatedGridCols.round();

  /// 排序态网格（固定 delegate、不参与 morph）所需的宽高比。
  double get targetChildAspectRatio {
    final cardHeight = targetCardWidth + animatedGridTextHeight;
    return (cardHeight > 0 && targetCardWidth > 0)
        ? targetCardWidth / cardHeight
        : 1.0;
  }
}

typedef ZoomLayoutMetrics = FolderZoomLayoutMetrics;

/// 网格 ↔ 列表内容交接的滞回上界。
const double kFolderZoomContentHandoffUpper = 0.55;

/// 交接滞回下界。
const double kFolderZoomContentHandoffLower = 0.45;

/// 交接点两侧压暗半窗。
const double kFolderZoomContentHandoffFadeHalfWindow = 0.12;

/// 交接瞬间的内容不透明度下限。
const double kFolderZoomContentHandoffMinOpacity = 0.55;

/// Animates [FolderZoomLayoutMetrics] smoothly whenever `zoomScale` changes,
/// and returns the sliver built by [builder].
class FolderZoomSliverBuilder extends StatefulWidget {
  const FolderZoomSliverBuilder({
    super.key,
    required this.zoomScale,
    required this.width,
    required this.builder,
  });

  final double zoomScale;
  final double width;
  final Widget Function(BuildContext context, FolderZoomLayoutMetrics metrics)
      builder;

  @override
  State<FolderZoomSliverBuilder> createState() =>
      _FolderZoomSliverBuilderState();
}

typedef ZoomSliverBuilder = FolderZoomSliverBuilder;

typedef _ZoomTargets = ({
  double zoomScale,
  double gridMorph,
  double compactMorph,
  double gridCols,
  double gridTextHeight,
  double listExtent,
  double cardWidth,
  double titleFontSize,
  double subtitleFontSize,
  double infoFontSize,
});

class _FolderZoomSliverBuilderState extends State<FolderZoomSliverBuilder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late CurvedAnimation _curved;

  late double _fromZoomScale;
  late double _toZoomScale;

  late double _fromGridMorph;
  late double _toGridMorph;

  late double _fromCompactMorph;
  late double _toCompactMorph;

  late double _fromGridCols;
  late double _toGridCols;

  late double _fromGridTextHeight;
  late double _toGridTextHeight;

  late double _fromListExtent;
  late double _toListExtent;

  late double _fromTitleFontSize;
  late double _toTitleFontSize;

  late double _fromSubtitleFontSize;
  late double _toSubtitleFontSize;

  late double _fromInfoFontSize;
  late double _toInfoFontSize;

  double _targetCardWidth = 0.0;

  bool _initialized = false;
  int _contentSide = 0;

  List<({_ZoomTargets targets, double weight})> _geometryFrom = const [];
  _ZoomTargets? _geometryTo;

  final FolderZoomViewportTracker _viewportTracker =
      FolderZoomViewportTracker();

  double _startSliverOffset = 0.0;
  double _targetSliverOffset = 0.0;
  double _startScrollPixels = 0.0;
  double _targetScrollPixels = 0.0;

  FolderZoomPinchController? _activePinchController;
  bool _pinchAnchorInitialized = false;
  double _pinchBasePixels = 0.0;
  double _pinchBaseSliverOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(_onTick);
    _curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  void _onTick() {
    if (mounted) {
      if (_controller.isAnimating &&
          (_startScrollPixels - _targetScrollPixels).abs() > 0.5) {
        final position = Scrollable.maybeOf(context)?.position;
        if (position != null &&
            position.hasPixels &&
            _viewportTracker.isActiveInViewport) {
          final target = lerpDouble(
            _startScrollPixels,
            _targetScrollPixels,
            _curved.value,
          )!;
          final clamped = target.clamp(0.0, position.maxScrollExtent);
          if ((position.pixels - clamped).abs() > 0.5) {
            position.jumpTo(clamped);
          }
        }
      }
      setState(() {});
    }
  }

  void _onPinchChanged() {
    final pinch = _activePinchController;
    if (!mounted || pinch == null) return;
    if (pinch.isActive) {
      final position = Scrollable.maybeOf(context)?.position;
      if (position != null &&
          position.hasPixels &&
          _viewportTracker.isActiveInViewport) {
        if (!_pinchAnchorInitialized) {
          _pinchBasePixels = position.pixels;
          _pinchBaseSliverOffset = _viewportTracker.viewportTop;
          _pinchAnchorInitialized = true;
        }
        final isPortrait =
            MediaQuery.maybeOrientationOf(context) == Orientation.portrait;
        final targetsTo = _calculateTargets(
          pinch.targetZoomScale,
          isPortrait: isPortrait,
        );
        final toLayer = _layerOf(targetsTo, 1.0);
        final targetSliverOffset = _viewportTracker.viewportTopForLayer(
          toLayer,
          usableWidth: _viewportTracker.usableWidth > 0
              ? _viewportTracker.usableWidth
              : widget.width,
          outerWidth: widget.width,
          isPortrait: isPortrait,
        );
        final delta = targetSliverOffset - _pinchBaseSliverOffset;
        final targetPixels =
            (_pinchBasePixels + delta * pinch.progress).clamp(
          0.0,
          position.maxScrollExtent,
        );
        if ((position.pixels - targetPixels).abs() > 0.5) {
          position.jumpTo(targetPixels);
        }
      }
    } else {
      _pinchAnchorInitialized = false;
    }
  }

  double _eval(double from, double to) =>
      lerpDouble(from, to, _curved.value) ?? to;

  static FolderZoomGeometryLayer _layerOf(_ZoomTargets targets, double weight) {
    return FolderZoomGeometryLayer(
      isGrid: targets.gridMorph >= 1.0,
      crossAxisCount: targets.gridCols.round().clamp(1, 12),
      gridTextHeight: targets.gridTextHeight,
      listExtent: targets.listExtent,
      weight: weight,
    );
  }

  static FolderZoomLayoutMetrics _endpointMetrics(
    _ZoomTargets targets, {
    required bool isPortrait,
    required double outerWidth,
  }) {
    final bool isGrid = targets.gridMorph >= 0.5;
    return FolderZoomLayoutMetrics(
      targetZoomScale: targets.zoomScale,
      animatedZoomScale: targets.zoomScale,
      gridMorph: targets.gridMorph,
      compactMorph: targets.compactMorph,
      animatedGridCols: targets.gridCols,
      animatedGridTextHeight: targets.gridTextHeight,
      animatedListExtent: targets.listExtent,
      targetCardWidth: targets.cardWidth,
      animatedTitleFontSize: quantizeFolderZoomFontSize(targets.titleFontSize),
      animatedSubtitleFontSize:
          quantizeFolderZoomFontSize(targets.subtitleFontSize),
      animatedInfoFontSize: quantizeFolderZoomFontSize(targets.infoFontSize),
      isPortrait: isPortrait,
      outerWidth: outerWidth,
      contentIsGrid: isGrid,
      contentReveal: 1.0,
      geometryLayers: [_layerOf(targets, 1.0)],
    );
  }

  static const double _kGeometryLayerMinWeight = 0.02;

  static void _addOrMergeLayer(
    List<({_ZoomTargets targets, double weight})> list,
    _ZoomTargets targets,
    double weight,
  ) {
    for (var i = 0; i < list.length; i++) {
      if ((list[i].targets.zoomScale - targets.zoomScale).abs() < 1e-4) {
        list[i] = (targets: targets, weight: list[i].weight + weight);
        return;
      }
    }
    list.add((targets: targets, weight: weight));
  }

  void _collapseGeometry(double progress) {
    final double p = progress.clamp(0.0, 1.0);
    final double inverse = 1.0 - p;
    final collapsed = <({_ZoomTargets targets, double weight})>[];

    for (final layer in _geometryFrom) {
      final double weight = layer.weight * inverse;
      if (weight > _kGeometryLayerMinWeight) {
        _addOrMergeLayer(collapsed, layer.targets, weight);
      }
    }
    final current = _geometryTo;
    if (current != null && p > _kGeometryLayerMinWeight) {
      _addOrMergeLayer(collapsed, current, p);
    }

    if (collapsed.isEmpty) {
      final fallback =
          current ?? (_geometryFrom.isNotEmpty ? _geometryFrom.last.targets : null);
      if (fallback != null) {
        _geometryFrom = [(targets: fallback, weight: 1.0)];
      }
      return;
    }

    final double sum =
        collapsed.fold<double>(0.0, (total, layer) => total + layer.weight);
    if (sum <= 0.0) return;
    if ((sum - 1.0).abs() > 1e-6) {
      for (var i = 0; i < collapsed.length; i++) {
        collapsed[i] = (
          targets: collapsed[i].targets,
          weight: collapsed[i].weight / sum,
        );
      }
    }
    _geometryFrom = collapsed;
  }

  List<FolderZoomGeometryLayer> _effectiveGeometryLayers(double progress) {
    final double p = progress.clamp(0.0, 1.0);
    final double inverse = 1.0 - p;
    final current = _geometryTo;

    if (!_controller.isAnimating) {
      final settled = current ??
          (_geometryFrom.isNotEmpty ? _geometryFrom.last.targets : _targets());
      return [_layerOf(settled, 1.0)];
    }

    final merged = <({_ZoomTargets targets, double weight})>[];
    for (final layer in _geometryFrom) {
      final double weight = layer.weight * inverse;
      _addOrMergeLayer(merged, layer.targets, weight);
    }
    if (current != null) {
      _addOrMergeLayer(merged, current, p);
    }

    final layers = <FolderZoomGeometryLayer>[
      for (final entry in merged) _layerOf(entry.targets, entry.weight),
    ];

    if (layers.isEmpty) {
      final fallback = current ??
          (_geometryFrom.isNotEmpty ? _geometryFrom.last.targets : _targets());
      layers.add(_layerOf(fallback, 1.0));
    }
    return layers;
  }

  List<FolderZoomGeometryLayer> _pinchGeometryLayers(
    _ZoomTargets from,
    _ZoomTargets to,
    double progress,
  ) {
    final double t = progress.clamp(0.0, 1.0);
    return [_layerOf(from, 1.0 - t), _layerOf(to, t)];
  }

  ({bool isGrid, double reveal}) _resolveContentHandoff(double morph) {
    final int side;
    if (morph >= kFolderZoomContentHandoffUpper) {
      side = 1;
    } else if (morph <= kFolderZoomContentHandoffLower) {
      side = -1;
    } else {
      side = _contentSide != 0 ? _contentSide : (morph >= 0.5 ? 1 : -1);
    }
    _contentSide = side;

    final double distance = (morph - 0.5).abs();
    final double reveal = distance >= kFolderZoomContentHandoffFadeHalfWindow
        ? 1.0
        : kFolderZoomContentHandoffMinOpacity +
              (1.0 - kFolderZoomContentHandoffMinOpacity) *
                  (distance / kFolderZoomContentHandoffFadeHalfWindow);
    return (isGrid: side > 0, reveal: reveal);
  }

  _ZoomTargets _calculateTargets(
    double zoomScale, {
    bool? isPortrait,
    double? textScale,
  }) {
    final snapped = snapFolderZoomScale(zoomScale);
    final portrait = isPortrait ??
        (MediaQuery.maybeOrientationOf(context) == Orientation.portrait);
    final scaled = textScale ?? folderZoomTextScaleOf(context);
    final tier = getFolderZoomTier(snapped);
    final gridCols = FolderZoomPolicy.calculateCrossAxisCount(
      width: widget.width,
      tier: tier,
      isPortrait: portrait,
    );
    final cardWidth = FolderZoomPolicy.gridCardWidth(
      contentWidth: math.max(
        1.0,
        widget.width - kGridHorizontalPadding * 2,
      ),
      crossAxisCount: gridCols,
    );
    final fontSizes = resolveFolderZoomFontSizes(
      tier: tier,
      cardWidth: cardWidth,
      isPortrait: portrait,
    );
    return (
      zoomScale: snapped,
      gridMorph: isFolderZoomGrid(snapped) ? 1.0 : 0.0,
      compactMorph: isFolderZoomCompactList(snapped) ? 1.0 : 0.0,
      gridCols: gridCols.toDouble(),
      gridTextHeight: folderZoomGridTextHeightFor(
        tier: tier,
        isPortrait: portrait,
        textScale: scaled,
      ),
      listExtent: getFolderListTileExtent(snapped),
      cardWidth: cardWidth,
      titleFontSize: fontSizes.title,
      subtitleFontSize: fontSizes.subtitle,
      infoFontSize: fontSizes.info,
    );
  }

  final Map<double, _ZoomTargets> _pinchTargetsCache = <double, _ZoomTargets>{};
  double _pinchCacheWidth = -1;
  bool _pinchCacheIsPortrait = false;
  double _pinchCacheTextScale = -1;

  _ZoomTargets _cachedTargets(
    double zoomScale, {
    required bool isPortrait,
    required double textScale,
  }) {
    if (_pinchCacheWidth != widget.width ||
        _pinchCacheIsPortrait != isPortrait ||
        _pinchCacheTextScale != textScale) {
      _pinchTargetsCache.clear();
      _pinchCacheWidth = widget.width;
      _pinchCacheIsPortrait = isPortrait;
      _pinchCacheTextScale = textScale;
    }
    return _pinchTargetsCache.putIfAbsent(
      zoomScale,
      () => _calculateTargets(
        zoomScale,
        isPortrait: isPortrait,
        textScale: textScale,
      ),
    );
  }

  _ZoomTargets _targets() => _calculateTargets(widget.zoomScale);

  void _applyTargets(_ZoomTargets targets, {required bool animate}) {
    _targetCardWidth = targets.cardWidth;

    if (animate) {
      _collapseGeometry(_curved.value);
      _fromZoomScale = _eval(_fromZoomScale, _toZoomScale);
      _fromGridMorph = _eval(_fromGridMorph, _toGridMorph);
      _fromCompactMorph = _eval(_fromCompactMorph, _toCompactMorph);
      _fromGridCols = _eval(_fromGridCols, _toGridCols);
      _fromGridTextHeight = _eval(_fromGridTextHeight, _toGridTextHeight);
      _fromListExtent = _eval(_fromListExtent, _toListExtent);
      _fromTitleFontSize = _eval(_fromTitleFontSize, _toTitleFontSize);
      _fromSubtitleFontSize = _eval(_fromSubtitleFontSize, _toSubtitleFontSize);
      _fromInfoFontSize = _eval(_fromInfoFontSize, _toInfoFontSize);

      final isPortrait =
          MediaQuery.maybeOrientationOf(context) == Orientation.portrait;
      final targetLayer = _layerOf(targets, 1.0);
      final double targetSliverOffset = _viewportTracker.viewportTopForLayer(
        targetLayer,
        usableWidth: _viewportTracker.usableWidth > 0
            ? _viewportTracker.usableWidth
            : widget.width,
        outerWidth: widget.width,
        isPortrait: isPortrait,
      );
      final double currentSliverOffset = _controller.isAnimating
          ? (lerpDouble(_startSliverOffset, _targetSliverOffset, _curved.value) ??
              _viewportTracker.viewportTop)
          : _viewportTracker.viewportTop;
      _startSliverOffset = currentSliverOffset;
      _targetSliverOffset = targetSliverOffset;

      final position = Scrollable.maybeOf(context)?.position;
      if (position != null &&
          position.hasPixels &&
          _viewportTracker.isActiveInViewport) {
        final currentPixels = position.pixels;
        _startScrollPixels = currentPixels;
        _targetScrollPixels =
            currentPixels + (_targetSliverOffset - _startSliverOffset);
      } else {
        _startScrollPixels = 0.0;
        _targetScrollPixels = 0.0;
      }
    } else {
      _fromZoomScale = _toZoomScale = widget.zoomScale;
      _fromGridMorph = _toGridMorph = targets.gridMorph;
      _fromCompactMorph = _toCompactMorph = targets.compactMorph;
      _fromGridCols = _toGridCols = targets.gridCols;
      _fromGridTextHeight = _toGridTextHeight = targets.gridTextHeight;
      _fromListExtent = _toListExtent = targets.listExtent;
      _fromTitleFontSize = _toTitleFontSize = targets.titleFontSize;
      _fromSubtitleFontSize = _toSubtitleFontSize = targets.subtitleFontSize;
      _fromInfoFontSize = _toInfoFontSize = targets.infoFontSize;
      _geometryFrom = [(targets: targets, weight: 1.0)];
      _geometryTo = targets;
      _startSliverOffset = _targetSliverOffset = _viewportTracker.viewportTop;
      _startScrollPixels = _targetScrollPixels = 0.0;
      return;
    }

    _toZoomScale = widget.zoomScale;
    _toGridMorph = targets.gridMorph;
    _toCompactMorph = targets.compactMorph;
    _toGridCols = targets.gridCols;
    _toGridTextHeight = targets.gridTextHeight;
    _toListExtent = targets.listExtent;
    _toTitleFontSize = targets.titleFontSize;
    _toSubtitleFontSize = targets.subtitleFontSize;
    _toInfoFontSize = targets.infoFontSize;
    _geometryTo = targets;

    _controller.forward(from: 0.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pinch = FolderZoomPinchScope.maybeOf(context);
    if (pinch != _activePinchController) {
      _activePinchController?.removeListener(_onPinchChanged);
      _activePinchController = pinch;
      _activePinchController?.addListener(_onPinchChanged);
    }
    if (_initialized) return;
    _applyTargets(_targets(), animate: false);
    _initialized = true;
  }

  @override
  void didUpdateWidget(FolderZoomSliverBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);

    final bool scaleChanged =
        (oldWidget.zoomScale - widget.zoomScale).abs() > 1e-4;
    final bool widthChanged = (oldWidget.width - widget.width).abs() > 0.5;
    if (!scaleChanged && !widthChanged) return;

    final targets = _targets();
    final pinch = FolderZoomPinchScope.maybeOf(context);

    if (scaleChanged) {
      if (pinch != null &&
          pinch.committedScale != null &&
          (pinch.committedScale! - widget.zoomScale).abs() < 1e-4) {
        _applyTargets(targets, animate: false);
      } else {
        _applyTargets(targets, animate: true);
      }
    } else if (widthChanged) {
      _fromGridCols = _toGridCols = targets.gridCols;
      _fromGridTextHeight = _toGridTextHeight = targets.gridTextHeight;
      _fromTitleFontSize = _toTitleFontSize = targets.titleFontSize;
      _fromSubtitleFontSize = _toSubtitleFontSize = targets.subtitleFontSize;
      _fromInfoFontSize = _toInfoFontSize = targets.infoFontSize;
      _targetCardWidth = targets.cardWidth;
      _geometryFrom = [(targets: targets, weight: 1.0)];
      _geometryTo = targets;
    }
  }

  @override
  void dispose() {
    _activePinchController?.removeListener(_onPinchChanged);
    _activePinchController = null;
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait =
        MediaQuery.maybeOrientationOf(context) == Orientation.portrait;
    final textScale = folderZoomTextScaleOf(context);

    final pinch = FolderZoomPinchScope.maybeOf(context);
    if (pinch != null && pinch.isActive) {
      final fromScale = pinch.baseZoomScale;
      final toScale = pinch.targetZoomScale;
      final targetsFrom = _cachedTargets(
        fromScale,
        isPortrait: isPortrait,
        textScale: textScale,
      );
      final targetsTo = _cachedTargets(
        toScale,
        isPortrait: isPortrait,
        textScale: textScale,
      );
      final t = pinch.progress;
      final activeTarget = t > 0.5 ? toScale : fromScale;
      final double gridMorph =
          (lerpDouble(targetsFrom.gridMorph, targetsTo.gridMorph, t) ??
                  targetsFrom.gridMorph)
              .clamp(0.0, 1.0);
      final handoff = _resolveContentHandoff(gridMorph);

      final metrics = FolderZoomLayoutMetrics(
        targetZoomScale: activeTarget,
        animatedZoomScale:
            lerpDouble(fromScale, toScale, t) ?? fromScale,
        gridMorph: gridMorph,
        compactMorph:
            (lerpDouble(targetsFrom.compactMorph, targetsTo.compactMorph, t) ??
                    targetsFrom.compactMorph)
                .clamp(0.0, 1.0),
        animatedGridCols:
            lerpDouble(targetsFrom.gridCols, targetsTo.gridCols, t) ??
            targetsFrom.gridCols,
        animatedGridTextHeight:
            lerpDouble(
              targetsFrom.gridTextHeight,
              targetsTo.gridTextHeight,
              t,
            ) ??
            targetsFrom.gridTextHeight,
        animatedListExtent:
            lerpDouble(targetsFrom.listExtent, targetsTo.listExtent, t) ??
            targetsFrom.listExtent,
        targetCardWidth: t > 0.5 ? targetsTo.cardWidth : targetsFrom.cardWidth,
        animatedTitleFontSize: quantizeFolderZoomFontSize(
          lerpDouble(targetsFrom.titleFontSize, targetsTo.titleFontSize, t) ??
              targetsFrom.titleFontSize,
        ),
        animatedSubtitleFontSize: quantizeFolderZoomFontSize(
          lerpDouble(
                targetsFrom.subtitleFontSize,
                targetsTo.subtitleFontSize,
                t,
              ) ??
              targetsFrom.subtitleFontSize,
        ),
        animatedInfoFontSize: quantizeFolderZoomFontSize(
          lerpDouble(targetsFrom.infoFontSize, targetsTo.infoFontSize, t) ??
              targetsFrom.infoFontSize,
        ),
        isPortrait: isPortrait,
        outerWidth: widget.width,
        contentIsGrid: handoff.isGrid,
        contentReveal: handoff.reveal,
        geometryLayers: _pinchGeometryLayers(targetsFrom, targetsTo, t),
        zoomScaleDelta: toScale - fromScale,
        startEndpointMetrics: _endpointMetrics(
          targetsFrom,
          isPortrait: isPortrait,
          outerWidth: widget.width,
        ),
        targetEndpointMetrics: _endpointMetrics(
          targetsTo,
          isPortrait: isPortrait,
          outerWidth: widget.width,
        ),
        viewportTracker: _viewportTracker,
      );
      return widget.builder(context, metrics);
    }

    final double progress = _curved.value;
    final double gridMorph = _eval(
      _fromGridMorph,
      _toGridMorph,
    ).clamp(0.0, 1.0);
    final handoff = _resolveContentHandoff(gridMorph);
    final endTargets = _geometryTo ??
        (_geometryFrom.isNotEmpty ? _geometryFrom.last.targets : _targets());
    final startTargets = _geometryFrom.firstWhere(
      (entry) =>
          (entry.targets.zoomScale - endTargets.zoomScale).abs() > 1e-4,
      orElse: () => (targets: endTargets, weight: 1.0),
    ).targets;

    final metrics = FolderZoomLayoutMetrics(
      targetZoomScale: widget.zoomScale,
      animatedZoomScale: _eval(_fromZoomScale, _toZoomScale),
      gridMorph: gridMorph,
      compactMorph: _eval(_fromCompactMorph, _toCompactMorph).clamp(0.0, 1.0),
      animatedGridCols: _eval(_fromGridCols, _toGridCols),
      animatedGridTextHeight: _eval(_fromGridTextHeight, _toGridTextHeight),
      animatedListExtent: _eval(_fromListExtent, _toListExtent),
      targetCardWidth: _targetCardWidth,
      animatedTitleFontSize: quantizeFolderZoomFontSize(
        _eval(_fromTitleFontSize, _toTitleFontSize),
      ),
      animatedSubtitleFontSize: quantizeFolderZoomFontSize(
        _eval(_fromSubtitleFontSize, _toSubtitleFontSize),
      ),
      animatedInfoFontSize: quantizeFolderZoomFontSize(
        _eval(_fromInfoFontSize, _toInfoFontSize),
      ),
      isPortrait: isPortrait,
      outerWidth: widget.width,
      contentIsGrid: handoff.isGrid,
      contentReveal: handoff.reveal,
      geometryLayers: _effectiveGeometryLayers(progress),
      zoomScaleDelta: _toZoomScale - _fromZoomScale,
      startEndpointMetrics: _endpointMetrics(
        startTargets,
        isPortrait: isPortrait,
        outerWidth: widget.width,
      ),
      targetEndpointMetrics: _endpointMetrics(
        endTargets,
        isPortrait: isPortrait,
        outerWidth: widget.width,
      ),
      viewportTracker: _viewportTracker,
    );
    return widget.builder(context, metrics);
  }
}

/// [SliverGridDelegate]：把条目摆到若干**确定**档位布局（[FolderZoomGeometryLayer]）
/// 的加权位置上。
class SliverAnimatedZoomGridDelegate extends SliverGridDelegate {
  const SliverAnimatedZoomGridDelegate({
    required this.metrics,
    this.listMainAxisSpacing = kFolderListRowSpacing,
    this.gridCrossAxisSpacing = kGridCrossAxisSpacing,
    this.gridMainAxisSpacing = kGridMainAxisSpacing,
  });

  final FolderZoomLayoutMetrics metrics;
  final double listMainAxisSpacing;
  final double gridCrossAxisSpacing;
  final double gridMainAxisSpacing;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final usableWidth = math.max(1.0, constraints.crossAxisExtent);
    final viewportTop = constraints.scrollOffset;
    final viewportBottom =
        constraints.scrollOffset + constraints.remainingPaintExtent;
    final layers = metrics.resolvedGeometryLayers;
    final tracker = metrics.viewportTracker;
    if (tracker != null) {
      tracker.record(
        usableWidth: usableWidth,
        outerWidth: metrics.outerWidth,
        viewportTop: viewportTop,
        viewportBottom: viewportBottom,
        remainingPaintExtent: constraints.remainingPaintExtent,
        isAnimating: layers.length > 1,
        steadyLayer: layers.length == 1 ? layers.first : null,
        isPortrait: metrics.isPortrait,
      );
    }
    return _SliverAnimatedZoomGridLayout(
      usableWidth: usableWidth,
      outerWidth: metrics.outerWidth,
      isPortrait: metrics.isPortrait,
      viewportTop: viewportTop,
      viewportBottom: viewportBottom,
      layers: layers,
      listMainAxisSpacing: listMainAxisSpacing,
      gridCrossAxisSpacing: gridCrossAxisSpacing,
      gridMainAxisSpacing: gridMainAxisSpacing,
      tracker: tracker,
    );
  }

  @override
  bool shouldRelayout(SliverAnimatedZoomGridDelegate oldDelegate) {
    return !_sameLayers(
          oldDelegate.metrics.resolvedGeometryLayers,
          metrics.resolvedGeometryLayers,
        ) ||
        oldDelegate.metrics.outerWidth != metrics.outerWidth ||
        oldDelegate.metrics.isPortrait != metrics.isPortrait ||
        oldDelegate.listMainAxisSpacing != listMainAxisSpacing ||
        oldDelegate.gridCrossAxisSpacing != gridCrossAxisSpacing ||
        oldDelegate.gridMainAxisSpacing != gridMainAxisSpacing;
  }

  static bool _sameLayers(
    List<FolderZoomGeometryLayer> a,
    List<FolderZoomGeometryLayer> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _SliverAnimatedZoomGridLayout extends SliverGridLayout {
  const _SliverAnimatedZoomGridLayout({
    required this.usableWidth,
    required this.outerWidth,
    required this.isPortrait,
    required this.viewportTop,
    required this.viewportBottom,
    required this.layers,
    required this.listMainAxisSpacing,
    required this.gridCrossAxisSpacing,
    required this.gridMainAxisSpacing,
    this.tracker,
  });

  final double usableWidth;
  final double outerWidth;
  final bool isPortrait;
  final double viewportTop;
  final double viewportBottom;
  final List<FolderZoomGeometryLayer> layers;
  final double listMainAxisSpacing;
  final double gridCrossAxisSpacing;
  final double gridMainAxisSpacing;
  final FolderZoomViewportTracker? tracker;

  bool get _hasSingleLayer => layers.length == 1;

  double _layerViewportTop(FolderZoomGeometryLayer layer) {
    if (tracker == null || !tracker!.hasMeasurement) return viewportTop;
    return tracker!.viewportTopForLayer(
      layer,
      usableWidth: usableWidth,
      outerWidth: outerWidth,
      isPortrait: isPortrait,
    );
  }

  double get _viewportHeight {
    if (tracker != null && tracker!.hasMeasurement) {
      return tracker!.viewportHeight;
    }
    return math.max(0.0, viewportBottom - viewportTop);
  }

  static bool isGeometryVisibleInViewport(
    SliverGridGeometry geometry,
    double viewportTop,
    double viewportBottom,
  ) {
    if (viewportBottom <= viewportTop + 0.5) return false;
    return geometry.trailingScrollOffset > viewportTop + 0.5 &&
        geometry.scrollOffset < viewportBottom - 0.5;
  }

  static ({double contentWidth, double originOffsetX}) _resolveLayerHorizontal(
    FolderZoomGeometryLayer layer, {
    required double usableWidth,
    required double outerWidth,
    required bool isPortrait,
  }) {
    if (outerWidth <= usableWidth + 0.5) {
      return (contentWidth: usableWidth, originOffsetX: 0.0);
    }
    final currentHPad = (outerWidth - usableWidth) * 0.5;
    final targetHPad = folderContentHorizontalPadding(
      isPortrait: isPortrait,
      gridMorph: layer.isGrid ? 1.0 : 0.0,
    );
    final layerWidth = math.max(1.0, outerWidth - targetHPad * 2.0);
    return (
      contentWidth: layerWidth,
      originOffsetX: targetHPad - currentHPad,
    );
  }

  static SliverGridGeometry geometryInLayer({
    required FolderZoomGeometryLayer layer,
    required int index,
    required double usableWidth,
    double outerWidth = 0.0,
    bool isPortrait = false,
    double listMainAxisSpacing = kFolderListRowSpacing,
    double gridCrossAxisSpacing = kGridCrossAxisSpacing,
    double gridMainAxisSpacing = kGridMainAxisSpacing,
  }) {
    final horizontal = _resolveLayerHorizontal(
      layer,
      usableWidth: usableWidth,
      outerWidth: outerWidth,
      isPortrait: isPortrait,
    );
    if (!layer.isGrid) {
      final stride = layer.listExtent + listMainAxisSpacing;
      return SliverGridGeometry(
        scrollOffset: index * stride,
        crossAxisOffset: horizontal.originOffsetX,
        mainAxisExtent: layer.listExtent,
        crossAxisExtent: horizontal.contentWidth,
      );
    }
    final cols = layer.crossAxisCount;
    final row = index ~/ cols;
    final col = index % cols;
    final cardWidth = FolderZoomPolicy.gridCardWidth(
      contentWidth: horizontal.contentWidth,
      crossAxisCount: cols,
      crossAxisSpacing: gridCrossAxisSpacing,
    );
    final cardHeight = cardWidth + layer.gridTextHeight;
    final mainStride = cardHeight + gridMainAxisSpacing;
    final crossStride = cardWidth + gridCrossAxisSpacing;

    return SliverGridGeometry(
      scrollOffset: row * mainStride,
      crossAxisOffset: horizontal.originOffsetX + col * crossStride,
      mainAxisExtent: cardHeight,
      crossAxisExtent: cardWidth,
    );
  }

  SliverGridGeometry _geometryIn(FolderZoomGeometryLayer layer, int index) {
    return geometryInLayer(
      layer: layer,
      index: index,
      usableWidth: usableWidth,
      outerWidth: outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: listMainAxisSpacing,
      gridCrossAxisSpacing: gridCrossAxisSpacing,
      gridMainAxisSpacing: gridMainAxisSpacing,
    );
  }

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    if (_hasSingleLayer) {
      return _geometryIn(layers.first, index);
    }
    SliverGridGeometry? firstVisibleGeometry;
    SliverGridGeometry? lastVisibleGeometry;
    bool visibleInTarget = false;
    int visibleCount = 0;
    double visibleWeight = 0.0;
    double scrollOffset = 0.0;
    double crossAxisOffset = 0.0;
    double mainAxisExtent = 0.0;
    double crossAxisExtent = 0.0;
    for (var i = 0; i < layers.length; i++) {
      final layer = layers[i];
      final geometry = _geometryIn(layer, index);
      final layerViewTop = _layerViewportTop(layer);
      final layerViewBottom = layerViewTop + _viewportHeight;
      if (isGeometryVisibleInViewport(geometry, layerViewTop, layerViewBottom)) {
        visibleCount++;
        firstVisibleGeometry ??= geometry;
        lastVisibleGeometry = geometry;
        if (i == layers.length - 1) {
          visibleInTarget = true;
        }
        visibleWeight += layer.weight;
        scrollOffset += geometry.scrollOffset * layer.weight;
        crossAxisOffset += geometry.crossAxisOffset * layer.weight;
        mainAxisExtent += geometry.mainAxisExtent * layer.weight;
        crossAxisExtent += geometry.crossAxisExtent * layer.weight;
      }
    }
    if (visibleCount == layers.length && visibleWeight > 1e-6) {
      final inv = 1.0 / visibleWeight;
      return SliverGridGeometry(
        scrollOffset: scrollOffset * inv,
        crossAxisOffset: crossAxisOffset * inv,
        mainAxisExtent: mainAxisExtent * inv,
        crossAxisExtent: crossAxisExtent * inv,
      );
    }
    if (visibleCount > 0) {
      if (visibleInTarget) {
        final lastGeom = lastVisibleGeometry!;
        final targetViewTop = _layerViewportTop(layers.last);
        final delta = viewportTop - targetViewTop;
        return SliverGridGeometry(
          scrollOffset: lastGeom.scrollOffset + delta,
          crossAxisOffset: lastGeom.crossAxisOffset,
          mainAxisExtent: lastGeom.mainAxisExtent,
          crossAxisExtent: lastGeom.crossAxisExtent,
        );
      } else {
        final firstGeom = firstVisibleGeometry!;
        final startViewTop = _layerViewportTop(layers.first);
        final delta = viewportTop - startViewTop;
        return SliverGridGeometry(
          scrollOffset: firstGeom.scrollOffset + delta,
          crossAxisOffset: firstGeom.crossAxisOffset,
          mainAxisExtent: firstGeom.mainAxisExtent,
          crossAxisExtent: firstGeom.crossAxisExtent,
        );
      }
    }
    return _geometryIn(layers.last, index);
  }

  double _mainStrideIn(FolderZoomGeometryLayer layer) => mainStrideFor(
        layer: layer,
        usableWidth: usableWidth,
        outerWidth: outerWidth,
        isPortrait: isPortrait,
        listMainAxisSpacing: listMainAxisSpacing,
        gridCrossAxisSpacing: gridCrossAxisSpacing,
        gridMainAxisSpacing: gridMainAxisSpacing,
      );

  static double mainStrideFor({
    required FolderZoomGeometryLayer layer,
    required double usableWidth,
    double outerWidth = 0.0,
    bool isPortrait = false,
    double listMainAxisSpacing = kFolderListRowSpacing,
    double gridCrossAxisSpacing = kGridCrossAxisSpacing,
    double gridMainAxisSpacing = kGridMainAxisSpacing,
  }) {
    if (!layer.isGrid) {
      return layer.listExtent + listMainAxisSpacing;
    }
    final horizontal = _resolveLayerHorizontal(
      layer,
      usableWidth: usableWidth,
      outerWidth: outerWidth,
      isPortrait: isPortrait,
    );
    final cardWidth = FolderZoomPolicy.gridCardWidth(
      contentWidth: horizontal.contentWidth,
      crossAxisCount: layer.crossAxisCount,
      crossAxisSpacing: gridCrossAxisSpacing,
    );
    return cardWidth + layer.gridTextHeight + gridMainAxisSpacing;
  }

  int _minIndexIn(FolderZoomGeometryLayer layer, double scrollOffset) =>
      minChildIndexIn(
        layer: layer,
        scrollOffset: scrollOffset,
        usableWidth: usableWidth,
        outerWidth: outerWidth,
        isPortrait: isPortrait,
        listMainAxisSpacing: listMainAxisSpacing,
        gridCrossAxisSpacing: gridCrossAxisSpacing,
        gridMainAxisSpacing: gridMainAxisSpacing,
      );

  static int minChildIndexIn({
    required FolderZoomGeometryLayer layer,
    required double scrollOffset,
    required double usableWidth,
    double outerWidth = 0.0,
    bool isPortrait = false,
    double listMainAxisSpacing = kFolderListRowSpacing,
    double gridCrossAxisSpacing = kGridCrossAxisSpacing,
    double gridMainAxisSpacing = kGridMainAxisSpacing,
  }) {
    if (scrollOffset <= 0.0) return 0;
    final stride = mainStrideFor(
      layer: layer,
      usableWidth: usableWidth,
      outerWidth: outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: listMainAxisSpacing,
      gridCrossAxisSpacing: gridCrossAxisSpacing,
      gridMainAxisSpacing: gridMainAxisSpacing,
    );
    if (stride <= 0.0) return 0;
    if (!layer.isGrid) {
      return math.max(0, scrollOffset ~/ stride);
    }
    return math.max(0, layer.crossAxisCount * (scrollOffset ~/ stride));
  }

  int _maxIndexIn(FolderZoomGeometryLayer layer, double targetEndScrollOffset) =>
      maxChildIndexIn(
        layer: layer,
        targetEndScrollOffset: targetEndScrollOffset,
        usableWidth: usableWidth,
        outerWidth: outerWidth,
        isPortrait: isPortrait,
        listMainAxisSpacing: listMainAxisSpacing,
        gridCrossAxisSpacing: gridCrossAxisSpacing,
        gridMainAxisSpacing: gridMainAxisSpacing,
      );

  static int maxChildIndexIn({
    required FolderZoomGeometryLayer layer,
    required double targetEndScrollOffset,
    required double usableWidth,
    double outerWidth = 0.0,
    bool isPortrait = false,
    double listMainAxisSpacing = kFolderListRowSpacing,
    double gridCrossAxisSpacing = kGridCrossAxisSpacing,
    double gridMainAxisSpacing = kGridMainAxisSpacing,
  }) {
    if (targetEndScrollOffset <= 0.0) return 0;
    final stride = mainStrideFor(
      layer: layer,
      usableWidth: usableWidth,
      outerWidth: outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: listMainAxisSpacing,
      gridCrossAxisSpacing: gridCrossAxisSpacing,
      gridMainAxisSpacing: gridMainAxisSpacing,
    );
    if (stride <= 0.0) return 0;
    if (!layer.isGrid) {
      return math.max(0, (targetEndScrollOffset / stride).ceil() - 1);
    }
    final rows = (targetEndScrollOffset / stride).ceil();
    return math.max(0, layer.crossAxisCount * rows - 1);
  }

  double _maxScrollOffsetIn(FolderZoomGeometryLayer layer, int childCount) {
    if (childCount <= 0) return 0.0;
    final stride = _mainStrideIn(layer);
    if (!layer.isGrid) {
      return childCount * stride - listMainAxisSpacing;
    }
    final rows = (childCount + layer.crossAxisCount - 1) ~/ layer.crossAxisCount;
    return rows * stride - gridMainAxisSpacing;
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    if (scrollOffset <= 0.0) return 0;
    var result = _minIndexIn(layers.first, _layerViewportTop(layers.first));
    for (var i = 1; i < layers.length; i++) {
      final candidate = _minIndexIn(layers[i], _layerViewportTop(layers[i]));
      if (candidate < result) result = candidate;
    }
    return result;
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    if (scrollOffset <= 0.0) return 0;
    var result = _maxIndexIn(
      layers.first,
      _layerViewportTop(layers.first) + _viewportHeight,
    );
    for (var i = 1; i < layers.length; i++) {
      final candidate = _maxIndexIn(
        layers[i],
        _layerViewportTop(layers[i]) + _viewportHeight,
      );
      if (candidate > result) result = candidate;
    }
    return result;
  }

  @override
  double computeMaxScrollOffset(int childCount) {
    if (childCount <= 0) return 0.0;
    if (_hasSingleLayer) {
      return _maxScrollOffsetIn(layers.first, childCount);
    }
    var total = 0.0;
    for (final layer in layers) {
      total += _maxScrollOffsetIn(layer, childCount) * layer.weight;
    }
    return total;
  }
}
