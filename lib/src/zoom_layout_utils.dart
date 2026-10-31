import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'zoom_debug.dart';
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

/// 单侧可见条目原地淡入淡出时的缩放幅度。
///
/// 只在一侧档位可见的条目不做位移，靠"不透明度 + 轻微缩放"进出；这个值是它们
/// 淡入 / 淡出全程的缩放差值（`1.0` → `1.0 - 0.15`）。
const double kFolderZoomFadeScaleDelta = 0.15;

/// 判定条目"在视口内"时两端各留的容差（像素）。
///
/// 只露出一两个像素的条目算不可见：把它锁在原地淡出会留下一条贴在边缘的残影。
const double kFolderZoomVisibilityEpsilon = 1.0;

/// 焦点默认高度（占视口高度的比例）：`0.5` 即视口中心。
const double kFolderZoomFocusCenter = 0.5;

/// 焦点锚相对内容两端的位置。
enum _ZoomAnchorEdge { none, top, bottom }

/// 记录 Sliver 最近一次视口范围与**焦点锚**，供档位过渡期间换算滚动距离、
/// 并判定条目在起止档位的可见性。
///
/// 锚定的不变量不是"某一条目原地不动"，而是**焦点处的那条内容不动**：
/// 记焦点屏幕高度为 `f`，焦点落在条目 `i` 的内部比例 `r` 处，则有
///
/// ```text
/// c         = viewportTop + f
/// i         = indexAt(c), r = (c - oA(i)) / strideA
/// targetTop = oB(i) + r * strideB - f
/// ```
///
/// 比例取**槽位步距**（条目高度 + 行间距）而不是条目高度：焦点经常落在行与行之间的
/// 空隙里，用条目高度会把比例压到 `1.0`，凭空产生一行的偏移。
///
/// 与"顶部条目锚定"只差 `r * (strideB - strideA)` —— 所有锚定策略的差别都收敛在焦点高度 `f` 上。
/// 焦点默认取视口中心（捏合时取双指中点），靠近顶/底一屏内渐变到 `0` / 视口底，
/// 于是两端自动退化成"顶部 / 底部对齐"，不会撞上滚动边界产生夹取跳变。
class FolderZoomViewportTracker {
  double usableWidth = 0.0;
  double outerWidth = 0.0;

  /// 视口顶端在 **sliver 坐标系**里的位置，每次布局都会刷新（不再冻结）。
  ///
  /// 等于 `pixels - precede`：列表上方还有 header / `SliverPadding` 时它是**负数**
  /// （起始边还在视口顶端之下）。不要用 `constraints.scrollOffset` 代替 ——
  /// 那个值被 Flutter 钳在 0，会把"列表起始边在视口下方"错当成"列表已贴顶"。
  double viewportTop = 0.0;
  double viewportBottom = 0.0;
  double remainingPaintExtent = 0.0;
  bool hasMeasurement = false;

  /// 焦点锚所在条目的索引。
  int anchorIndex = 0;

  /// 焦点落在锚条目内部的相对位置（`0.0` 顶部 ~ `1.0` 底部）。
  ///
  /// 以**槽位步距**（条目高度 + 行间距）为分母而不是条目高度：焦点经常落在
  /// 行与行之间的空隙里，用条目高度会把比例压到 `1.0` 并产生一行的偏移。
  double anchorRatio = 0.0;

  /// 焦点在视口中的 y 坐标（已按边界渐变过的实际值）。
  double anchorFocusY = 0.0;

  /// 锚是否贴在了内容的两端。贴边时直接按"顶 / 底对齐"换算，保证精确。
  _ZoomAnchorEdge _anchorEdge = _ZoomAnchorEdge.none;

  /// 贴边锚在**源档位**下的视口顶部偏移。
  ///
  /// 底部贴边时目标滚动位置不能靠"内容总高 − 视口高"来算（Sliver 的坐标里
  /// 含有外层 padding，会差出几十像素），改用两端内容总高之差平移，padding 自动抵消。
  double anchorSourceTop = 0.0;

  bool hasAnchor = false;

  /// 锚定假想的视口顶部与真实视口顶部的残差。
  ///
  /// 只有当滚动被 `maxScrollExtent` 夹住（长度变短、撞到底）时才会非零；
  /// 把它加回每一层的视口顶部，可见性判断才不会和屏幕上看到的内容打架。
  double correction = 0.0;

  /// Sliver 的条目总数，用于换算各档位的最大滚动偏移（由 `computeMaxScrollOffset` 回填）。
  int? contentCount;

  /// 读取当前滚动像素值的回调，由 [FolderZoomSliverBuilder] 注入。
  ///
  /// 布局回调里拿不到 [ScrollPosition]，但换档时要把"sliver 坐标"换算成"滚动像素"，
  /// 需要知道两者之间的固定差值（外层 padding / 前置 sliver 的高度）。这里记下每次
  /// 布局时刻的像素值，换档时就能把"当前像素"还原成同一时刻的 sliver 顶部。
  ///
  /// 少了它，过渡动画进行中再次换档会拿"当前像素"去配"上一帧的视口顶部"，
  /// 目标偏移被算高一整帧的量（实测触底连点两档会多算 290px，滚动越界后靠
  /// 回弹模拟慢慢弹回来）。
  double Function()? scrollPixelsReader;

  /// 最近一次布局时的滚动像素值。
  double? pixelsAtLayout;

  /// 最近一次稳态布局所在的档位层。
  FolderZoomGeometryLayer? steadyLayer;

  /// 行间距：由 delegate 在每次布局时回填，保证 tracker 的换算与真实布局一致。
  double listMainAxisSpacing = kFolderListRowSpacing;
  double gridCrossAxisSpacing = kGridCrossAxisSpacing;
  double gridMainAxisSpacing = kGridMainAxisSpacing;

  /// 视口高度。
  double get viewportHeight => math.max(0.0, viewportBottom - viewportTop);

  /// 该 sliver 之前的滚动内容长度（`pixels - viewportTop`，含外层 `SliverPadding`）。
  ///
  /// 稳态下是常量；它把"滚动像素"和"sliver 坐标"联系起来：
  /// `viewportTop = pixels - precede`。页面滚到最顶端时 `viewportTop == -precede`。
  double precede = 0.0;

  /// 视口顶端在 sliver 坐标里的最小值（= 页面 `pixels == 0` 时的取值）。
  ///
  /// 列表上方还有 header 时它是**负的**：`viewportTop` 落在 `[minViewportTop, ...]`
  /// 区间里都是合法的，夹取时不能按 0 截断，否则贴顶换档会把列表硬拽到页面最顶端。
  double get minViewportTop => -precede;

  /// 页面是否已经滚到最顶端。
  ///
  /// 只有这时才真的没有"向上滚"的余量，锚定才该退化成顶对齐。用
  /// `viewportTop <= 0.5` 判断是错的：列表起始边贴在视口顶端之下时它也是 0 或负数，
  /// 但那恰恰是应该正常补偿滚动的场景。
  bool get atScrollStart {
    final double? px = pixelsAtLayout;
    if (px != null) return px <= 0.5;
    return viewportTop <= 0.5;
  }

  /// 当前 Sliver 是否在视口中可见（用于多 Sliver 时仅激活可见 Sliver 的滚动吸附）。
  bool get isActiveInViewport => hasMeasurement && remainingPaintExtent > 10.0;

  /// 调试用：当前锚定方式的名称（`top` / `bottom` / `none`）。
  String get anchorEdgeName => _anchorEdge.name;

  void record({
    required double usableWidth,
    required double outerWidth,
    required double viewportTop,
    required double viewportBottom,
    required List<FolderZoomGeometryLayer> layers,
    bool isAnimating = false,
    double remainingPaintExtent = 0.0,
    bool isPortrait = false,
    double focusFraction = kFolderZoomFocusCenter,
    double listMainAxisSpacing = kFolderListRowSpacing,
    double gridCrossAxisSpacing = kGridCrossAxisSpacing,
    double gridMainAxisSpacing = kGridMainAxisSpacing,
  }) {
    final bool sizeChanged =
        !hasMeasurement || (this.outerWidth - outerWidth).abs() > 1.0;

    this.usableWidth = usableWidth;
    this.outerWidth = outerWidth;
    this.viewportTop = viewportTop;
    this.viewportBottom = viewportBottom;
    this.remainingPaintExtent = remainingPaintExtent;
    pixelsAtLayout = scrollPixelsReader?.call() ?? pixelsAtLayout;

    // 不变量：`viewportTop` 与 `position.pixels` 之间只差一个**常量**
    // —— 该 sliver 之前的滚动内容长度（`SliverPadding` 的 16px、上方的 header 高度…）。
    // 这个差值一旦变化，说明拿到的 ScrollPosition 根本不是布局本 sliver 的那个，
    // 后面所有"sliver 坐标 → 滚动像素"的换算都会崩（换档时会看到列表大幅上下移动）。
    final double? px = pixelsAtLayout;
    if (px != null) {
      final double precede = math.max(0.0, px - viewportTop);
      this.precede = precede;
      if (_lastPrecede == null || (precede - _lastPrecede!).abs() > 1.0) {
        zoomLog('align', () {
          return 'top=${zd(viewportTop)} px=${zd(px)} '
              'precede=${zd(precede)} '
              'delta=${_lastPrecede == null ? '-' : zd(precede - _lastPrecede!)} '
              'layers=${layers.length}';
        });
        _lastPrecede = precede;
      }
    }
    this.listMainAxisSpacing = listMainAxisSpacing;
    this.gridCrossAxisSpacing = gridCrossAxisSpacing;
    this.gridMainAxisSpacing = gridMainAxisSpacing;
    hasMeasurement = true;
    if (sizeChanged) hasAnchor = false;

    if (!isAnimating && layers.length == 1) {
      steadyLayer = layers.first;
      _recordAnchor(
        layers.first,
        focusFraction: focusFraction,
        isPortrait: isPortrait,
      );
      correction = 0.0;
      if (_wasMixing) {
        _wasMixing = false;
        zoomLog('layout', () {
          return 'settle top=${zd(viewportTop)} px=${zd(pixelsAtLayout)} '
              'anchor=${_anchorEdge.name}#$anchorIndex r=${zd(anchorRatio, 3)} '
              'f=${zd(anchorFocusY)} layer=${_layerTag(layers.first)} '
              'max=${zd(maxScrollOffsetFor(layers.first, isPortrait: isPortrait))}';
        });
      }
      return;
    }
    _wasMixing = true;

    if (!hasAnchor || layers.isEmpty) return;

    // 过渡期保留锚，只把"假想视口"与真实视口的残差算出来。
    double assumed = 0.0;
    double weight = 0.0;
    for (final layer in layers) {
      assumed += _anchorTopIn(layer, isPortrait: isPortrait) * layer.weight;
      weight += layer.weight;
    }
    if (weight > 1e-6) {
      correction = viewportTop - assumed / weight;
    }
    zoomLog('layout', () {
      double mixExtent = 0.0;
      for (final layer in layers) {
        mixExtent += _contentExtentOf(layer, isPortrait: isPortrait) * layer.weight;
      }
      return 'mix top=${zd(viewportTop)} px=${zd(pixelsAtLayout)} '
          'assumed=${weight > 1e-6 ? zd(assumed / weight) : 'n/a'} '
          'corr=${zd(correction)} anchor=${_anchorEdge.name}#$anchorIndex '
          'r=${zd(anchorRatio, 3)} f=${zd(anchorFocusY)} '
          'vh=${zd(viewportHeight)} '
          'maxMix=${zd(math.max(0.0, mixExtent - viewportHeight))} '
          'layers=${layers.map(_layerTag).join(',')}';
    });
  }

  /// 过渡期是否处于"多几何层混合"状态；用于只在过渡结束那一帧打一次日志。
  bool _wasMixing = false;

  /// 上一次布局时 `pixels - scrollOffset` 的值；恒定才算对齐，变化就说明挑错了位置。
  double? _lastPrecede;

  /// 几何层的简短标记，例如 `lx1/w1.00/e74.0`、`gx4/w0.00/th0.0`。
  static String _layerTag(FolderZoomGeometryLayer layer) {
    final head = '${layer.isGrid ? 'g' : 'l'}x${layer.crossAxisCount}'
        '/w${layer.weight.toStringAsFixed(2)}';
    return layer.isGrid
        ? '$head/th${layer.gridTextHeight.toStringAsFixed(1)}'
        : '$head/e${layer.listExtent.toStringAsFixed(1)}';
  }

  /// 用新的焦点高度重新计算锚点（捏合开始时按手指位置重新取锚）。
  void refreshAnchor({
    double focusFraction = kFolderZoomFocusCenter,
    bool isPortrait = false,
  }) {
    final layer = steadyLayer;
    if (layer == null || !hasMeasurement) return;
    _recordAnchor(layer, focusFraction: focusFraction, isPortrait: isPortrait);
  }

  void _recordAnchor(
    FolderZoomGeometryLayer layer, {
    required double focusFraction,
    required bool isPortrait,
  }) {
    final double height = viewportHeight;
    if (height <= 1.0) return;

    hasAnchor = true;
    anchorSourceTop = viewportTop;

    // 贴住两端时直接记成"顶 / 底对齐"，换算精确到像素，且不会因为
    // 焦点落在最后一条的槽位里而少滚一行。
    //
    // 顶端的判据是"页面已经滚到最顶端"（再没有向上滚的余量），而不是
    // `viewportTop <= 0.5`：列表上方还有 header / padding 时，起始边贴在视口顶端
    // **之下**也会让 `viewportTop` 等于 0 或负数，那种情况恰恰要正常按焦点补偿滚动。
    if (atScrollStart) {
      _anchorEdge = _ZoomAnchorEdge.top;
      anchorIndex = 0;
      anchorRatio = 0.0;
      anchorFocusY = 0.0;
      return;
    }
    final double? maxOffset = maxScrollOffsetFor(layer, isPortrait: isPortrait);
    if (maxOffset != null && maxOffset > 0.5 && viewportTop >= maxOffset - 0.5) {
      _anchorEdge = _ZoomAnchorEdge.bottom;
      anchorIndex = 0;
      anchorRatio = 1.0;
      anchorFocusY = height;
      return;
    }

    _anchorEdge = _ZoomAnchorEdge.none;

    double focus = _resolveFocusY(
      height,
      focusFraction,
      layer: layer,
      isPortrait: isPortrait,
    );
    // 列表起始边还在视口顶端之下（上方有 header、页面刚打开）时，焦点**上方没有
    // 内容**：把焦点压到第一条上，解出来的目标就等于"把起始边钉在原地"，
    // 不会把页面莫名往下滚一屏。
    focus = math.max(focus, -viewportTop);
    final double contentPoint = viewportTop + focus;

    final int index = _SliverAnimatedZoomGridLayout.minChildIndexIn(
      layer: layer,
      scrollOffset: contentPoint,
      usableWidth: usableWidth,
      outerWidth: outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: listMainAxisSpacing,
      gridCrossAxisSpacing: gridCrossAxisSpacing,
      gridMainAxisSpacing: gridMainAxisSpacing,
    );
    final double stride = _strideOf(layer, isPortrait: isPortrait);
    final geom = _geomIn(layer, index, isPortrait: isPortrait);

    anchorIndex = index;
    anchorRatio = stride <= 0.5
        ? 0.0
        : ((contentPoint - geom.scrollOffset) / stride).clamp(0.0, 1.0);
    anchorFocusY = focus;
  }

  /// 按"距顶 / 距底不足一屏"把焦点渐变到 `0` / `1`，让两端退化为顶 / 底对齐。
  double _resolveFocusY(
    double height,
    double focusFraction, {
    required FolderZoomGeometryLayer layer,
    required bool isPortrait,
  }) {
    final double preferred = focusFraction.clamp(0.0, 1.0) * height;

    // 距顶不足一屏时把焦点渐变到 `0`，让顶端退化成"顶对齐"、不撞滚动边界。
    //
    // 但这个渐变只在**内容起始边已经被推到视口顶端之上**时才成立：上方还有
    // header 时起始边在视口顶端之下（`viewportTop < 0`），向上余量是整个 header，
    // 此时压焦点等于跳过补偿，用户看到的焦点内容会被整体甩走。这种情形交给
    // `_recordAnchor` 里的 `focus = max(focus, -viewportTop)` 兜底：焦点落到内容
    // 之外才退化成顶对齐，否则正常按焦点锚定。
    final double topBlend = viewportTop < 0.0
        ? 0.0
        : (1.0 - viewportTop / height).clamp(0.0, 1.0);
    double focus = lerpDouble(preferred, 0.0, topBlend)!;

    final double? maxOffset = maxScrollOffsetFor(layer, isPortrait: isPortrait);
    if (maxOffset != null && maxOffset > 1.0) {
      final double bottomBlend =
          (1.0 - (maxOffset - viewportTop) / height).clamp(0.0, 1.0);
      focus = lerpDouble(focus, height, bottomBlend)!;
    }
    return focus.clamp(0.0, height);
  }

  SliverGridGeometry _geomIn(
    FolderZoomGeometryLayer layer,
    int index, {
    required bool isPortrait,
  }) {
    return _SliverAnimatedZoomGridLayout.geometryInLayer(
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

  double _strideOf(FolderZoomGeometryLayer layer, {required bool isPortrait}) {
    return _SliverAnimatedZoomGridLayout.mainStrideFor(
      layer: layer,
      usableWidth: usableWidth,
      outerWidth: outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: listMainAxisSpacing,
      gridCrossAxisSpacing: gridCrossAxisSpacing,
      gridMainAxisSpacing: gridMainAxisSpacing,
    );
  }

  double _contentExtentOf(
    FolderZoomGeometryLayer layer, {
    required bool isPortrait,
  }) {
    return _SliverAnimatedZoomGridLayout.contentExtentIn(
      layer: layer,
      childCount: contentCount ?? 0,
      usableWidth: usableWidth,
      outerWidth: outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: listMainAxisSpacing,
      gridCrossAxisSpacing: gridCrossAxisSpacing,
      gridMainAxisSpacing: gridMainAxisSpacing,
    );
  }

  double _anchorTopIn(
    FolderZoomGeometryLayer layer, {
    required bool isPortrait,
  }) {
    switch (_anchorEdge) {
      case _ZoomAnchorEdge.top:
        // 页面已经在最顶端：目标就是"原地别动"，也就是把列表起始边钉在它此刻
        // 所在的屏幕位置上。直接返回 0 是不对的 —— 上方还有 header / padding 时，
        // 列表起始边的正确目标是个负数（`-precede` 起）。
        return anchorSourceTop;
      case _ZoomAnchorEdge.bottom:
        final source = steadyLayer;
        if (source == null) return viewportTop;
        return anchorSourceTop +
            _contentExtentOf(layer, isPortrait: isPortrait) -
            _contentExtentOf(source, isPortrait: isPortrait);
      case _ZoomAnchorEdge.none:
        break;
    }
    final geom = _geomIn(layer, anchorIndex, isPortrait: isPortrait);
    return geom.scrollOffset +
        anchorRatio * _strideOf(layer, isPortrait: isPortrait) -
        anchorFocusY;
  }

  /// 指定档位 [layer] 下锚定条目对应的视口顶部偏移（含过渡期残差修正，已夹取）。
  double viewportTopForLayer(
    FolderZoomGeometryLayer layer, {
    bool isPortrait = false,
  }) {
    if (!hasMeasurement || !hasAnchor) return viewportTop;
    double top = _anchorTopIn(layer, isPortrait: isPortrait) + correction;
    // 底部贴边时 `_anchorTopIn` 已由两端内容总高之差精确给出，不要再夹取。
    if (_anchorEdge != _ZoomAnchorEdge.bottom) {
      final double? maxOffset = maxScrollOffsetFor(layer, isPortrait: isPortrait);
      if (maxOffset != null) top = math.min(top, maxOffset);
    }
    // 下界是"页面滚到 0"对应的坐标，不是 0：上方还有 header / padding 时它是负的。
    // 按 0 截断会把贴顶换档的目标算成"往上滚一整个 header 的高度"。
    return math.max(minViewportTop, top);
  }

  /// 把焦点锚换算到 [layer] 档位的目标视口顶部偏移（不含残差修正、不夹取）。
  ///
  /// 过渡动画直接把它当作**目标**滚动位置，结束时的真实值再回填锚点。
  double solveViewportTopFor(
    FolderZoomGeometryLayer layer, {
    bool isPortrait = false,
  }) {
    if (!hasMeasurement || !hasAnchor) return viewportTop;
    return _anchorTopIn(layer, isPortrait: isPortrait);
  }

  /// [layer] 档位在条目总数固定时的最大滚动偏移。
  double? maxScrollOffsetFor(
    FolderZoomGeometryLayer layer, {
    bool isPortrait = false,
  }) {
    final int? count = contentCount;
    if (count == null || count <= 0) return null;
    final double extent = _SliverAnimatedZoomGridLayout.contentExtentIn(
      layer: layer,
      childCount: count,
      usableWidth: usableWidth,
      outerWidth: outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: listMainAxisSpacing,
      gridCrossAxisSpacing: gridCrossAxisSpacing,
      gridMainAxisSpacing: gridMainAxisSpacing,
    );
    return math.max(0.0, extent - viewportHeight);
  }

  /// 过渡开始时**一次性**冻结"哪些条目原地淡入淡出、锁在哪个屏幕位置"。
  ///
  /// [mixLayers] 是此刻屏幕上**实际生效**的几何层（过渡中再次换档时，它就是上一段
  /// 过渡的混合结果，而不是某个纯净档位），[targetLayer] / [targetViewportTop]
  /// 是本次过渡的终点。这样"锁在原位"的参照系始终是**上一帧真实画出来的位置**，
  /// 连点两档也不会让被锁定的条目瞬移 —— 已经锁定的条目由 [previous] 带过来。
  ///
  /// 判定必须一次算完并冻结（原因见 [FolderZoomItemPinning] 的文档）。
  FolderZoomItemPinning? buildPinning({
    required List<FolderZoomGeometryLayer> mixLayers,
    required FolderZoomGeometryLayer targetLayer,
    required double targetViewportTop,
    required bool isPortrait,
    FolderZoomItemPinning? previous,
    double previousProgress = 0.0,
  }) {
    final int count = contentCount ?? 0;
    final double height = viewportHeight;
    if (count <= 0 || !hasMeasurement || mixLayers.isEmpty) return null;
    if (height <= 1.0) return null;

    double weightSum = 0.0;
    FolderZoomGeometryLayer? dominant;
    for (final layer in mixLayers) {
      weightSum += layer.weight;
      if (dominant == null || layer.weight > dominant.weight) dominant = layer;
    }
    if (weightSum <= 1e-6 || dominant == null) return null;

    // 各层在当前锚定下对应的屏幕视口顶部，与布局侧换算屏幕位置的口径完全一致。
    final List<double> mixTops = <double>[
      for (final layer in mixLayers)
        viewportTopForLayer(layer, isPortrait: isPortrait),
    ];

    // 只为"可能出现在视口里"的条目做判定。可见范围必然落在各层
    // [视口上方一屏, 视口下方两屏] 之内，先按层算出索引区间并集，
    // 免得条目上万时给整张表算一遍几何。
    int lo = count - 1;
    int hi = 0;
    for (var i = 0; i < mixLayers.length; i++) {
      final layer = mixLayers[i];
      lo = math.min(
        lo,
        _minIndexFor(layer, mixTops[i] - height, isPortrait: isPortrait) -
            layer.crossAxisCount,
      );
      hi = math.max(
        hi,
        _maxIndexFor(layer, mixTops[i] + height * 2, isPortrait: isPortrait) +
            layer.crossAxisCount,
      );
    }
    lo = math.min(
      lo,
      _minIndexFor(
            targetLayer,
            targetViewportTop - height,
            isPortrait: isPortrait,
          ) -
          targetLayer.crossAxisCount,
    );
    hi = math.max(
      hi,
      _maxIndexFor(
            targetLayer,
            targetViewportTop + height * 2,
            isPortrait: isPortrait,
          ) +
          targetLayer.crossAxisCount,
    );
    lo = lo.clamp(0, count - 1);
    hi = hi.clamp(0, count - 1);
    if (hi < lo) return null;

    final List<_PinSegment> segments = <_PinSegment>[];
    int? segmentFirst;
    FolderZoomItemPin segmentKind = FolderZoomItemPin.shared;
    FolderZoomGeometryLayer segmentLayer = dominant;
    double segmentOpacityFrom = 0.0;
    final List<double> segmentTops = <double>[];

    void closeSegment(int lastIndex) {
      if (segmentFirst != null &&
          segmentKind != FolderZoomItemPin.shared &&
          segmentTops.length == lastIndex - segmentFirst! + 1) {
        segments.add(
          _PinSegment(
            first: segmentFirst!,
            last: lastIndex,
            kind: segmentKind,
            layer: segmentLayer,
            tops: Float64List.fromList(segmentTops),
            opacityFrom: segmentOpacityFrom,
          ),
        );
      }
      segmentFirst = null;
      segmentTops.clear();
    }

    for (var index = lo; index <= hi; index++) {
      FolderZoomItemPin kind;
      FolderZoomGeometryLayer lockedLayer;
      double lockedTop;
      double opacityFrom;

      // 上一段过渡还没跑完就再换一档：已经锁定的条目继续锁在**它此刻所在的
      // 屏幕位置**上（也就是上一帧真实画出来的位置），否则它会从锁定位置
      // 瞬移到"若没锁定本该在的混合位置"，直接跳一截。
      final previousSegment = previous?._segmentOf(index);
      if (previousSegment != null) {
        kind = previousSegment.kind;
        lockedLayer = previousSegment.layer;
        lockedTop = previousSegment.topOf(index);
        opacityFrom = previousSegment.opacityAt(previousProgress);
      } else {
        double weight = 0.0;
        double top = 0.0;
        double extent = 0.0;
        for (var i = 0; i < mixLayers.length; i++) {
          final layer = mixLayers[i];
          final geometry = _geomIn(layer, index, isPortrait: isPortrait);
          weight += layer.weight;
          top += (geometry.scrollOffset - mixTops[i]) * layer.weight;
          extent += geometry.mainAxisExtent * layer.weight;
        }
        if (weight <= 1e-6) continue;
        top /= weight;
        extent /= weight;

        final targetGeometry =
            _geomIn(targetLayer, index, isPortrait: isPortrait);
        final double targetTop =
            targetGeometry.scrollOffset - targetViewportTop;

        final bool visibleFrom = _isOnScreen(top, extent, height);
        final bool visibleTo =
            _isOnScreen(targetTop, targetGeometry.mainAxisExtent, height);

        kind = visibleFrom == visibleTo
            ? FolderZoomItemPin.shared
            : (visibleFrom
                ? FolderZoomItemPin.fadeOut
                : FolderZoomItemPin.fadeIn);
        lockedLayer = kind == FolderZoomItemPin.fadeOut
            ? dominant
            : targetLayer;
        // 淡出锁在"现在的位置"，淡入锁在"将要落到的位置"。
        lockedTop = kind == FolderZoomItemPin.fadeOut ? top : targetTop;
        opacityFrom = kind == FolderZoomItemPin.fadeOut ? 1.0 : 0.0;
      }

      if (segmentFirst == null ||
          kind != segmentKind ||
          (kind != FolderZoomItemPin.shared &&
              (opacityFrom != segmentOpacityFrom ||
                  lockedLayer != segmentLayer))) {
        if (segmentFirst != null) closeSegment(index - 1);
        segmentFirst = index;
        segmentKind = kind;
        segmentLayer = lockedLayer;
        segmentOpacityFrom = opacityFrom;
      }
      if (kind != FolderZoomItemPin.shared) {
        segmentTops.add(lockedTop);
      }
    }
    closeSegment(hi);

    if (segments.isEmpty) return null;
    return FolderZoomItemPinning(segments);
  }

  /// 条目（顶部 [top]、高度 [extent]）是否落在视口 `[0, height]` 内。
  static bool _isOnScreen(double top, double extent, double height) {
    return top < height - kFolderZoomVisibilityEpsilon &&
        top + extent > kFolderZoomVisibilityEpsilon;
  }

  int _minIndexFor(
    FolderZoomGeometryLayer layer,
    double scrollOffset, {
    required bool isPortrait,
  }) {
    return _SliverAnimatedZoomGridLayout.minChildIndexIn(
      layer: layer,
      scrollOffset: scrollOffset,
      usableWidth: usableWidth,
      outerWidth: outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: listMainAxisSpacing,
      gridCrossAxisSpacing: gridCrossAxisSpacing,
      gridMainAxisSpacing: gridMainAxisSpacing,
    );
  }

  int _maxIndexFor(
    FolderZoomGeometryLayer layer,
    double targetEndScrollOffset, {
    required bool isPortrait,
  }) {
    return _SliverAnimatedZoomGridLayout.maxChildIndexIn(
      layer: layer,
      targetEndScrollOffset: targetEndScrollOffset,
      usableWidth: usableWidth,
      outerWidth: outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: listMainAxisSpacing,
      gridCrossAxisSpacing: gridCrossAxisSpacing,
      gridMainAxisSpacing: gridMainAxisSpacing,
    );
  }
}

/// 条目在一次档位过渡里的处置方式。
enum FolderZoomItemPin {
  /// 起始 / 目标档位**都可见**：按各档位几何加权位移，全程不透明。
  shared,

  /// 只在起始档位可见：锁在起始屏幕位置**原地淡出**（不位移）。
  fadeOut,

  /// 只在目标档位可见：锁在目标屏幕位置**原地淡入**（不位移）。
  fadeIn,
}

/// 一次档位过渡开始时**冻结**下来的条目处置表。
///
/// 为什么要冻结：可见性是布尔量，而过渡期滚动位置要在几千像素上平移。若每帧重新
/// 判定，条目会反复翻转可见性，每翻一次位置就在"加权混合值"和"锁定的单档位值"
/// 之间瞬移一次 —— 观感就是所有条目一起"从下往上弹一下"（这正是 3cc4109 当初
/// 把整块单侧淡出删掉的直接原因）。改成"过渡开始算一次、全程复用"之后，锁定位置
/// 和判定结果都不再随帧变化，弹跳的成因就不存在了，单侧条目也能安心地原地淡入淡出。
///
/// 条目被分到 [FolderZoomItemPin.fadeOut] / [FolderZoomItemPin.fadeIn] 时，
/// 位置由布局侧锁死（见 `_SliverAnimatedZoomGridLayout.getGeometryForChildIndex`），
/// 不透明度与缩放由 [FolderZoomLayoutMetrics.resolveItemTransition] 给出。
@immutable
class FolderZoomItemPinning {
  const FolderZoomItemPinning(this._segments);

  /// 按索引升序排列的锁定区段（最多四段：淡出两段 + 淡入两段）。
  final List<_PinSegment> _segments;

  /// 没有任何条目需要原地淡入淡出（整段过渡都是纯位移）。
  bool get isEmpty => _segments.isEmpty;

  /// 锁定条目里最小的索引；没有则返回 `null`。
  int? get firstPinnedIndex => isEmpty ? null : _segments.first.first;

  /// 锁定条目里最大的索引；没有则返回 `null`。
  int? get lastPinnedIndex => isEmpty ? null : _segments.last.last;

  _PinSegment? _segmentOf(int index) {
    for (final segment in _segments) {
      if (index < segment.first) return null;
      if (index <= segment.last) return segment;
    }
    return null;
  }

  /// [index] 的处置方式；未被冻结到的条目（例如过渡中新滚进视口的）按 [shared] 处理。
  FolderZoomItemPin pinOf(int index) =>
      _segmentOf(index)?.kind ?? FolderZoomItemPin.shared;

  /// 锁定条目的完整信息（处置方式 / 冻结的屏幕顶部 / 所属档位层）。
  ///
  /// 布局侧一次拿全，避免三次线性扫描。
  ({
    FolderZoomItemPin kind,
    double top,
    FolderZoomGeometryLayer layer,
  })? pinInfoOf(int index) {
    final segment = _segmentOf(index);
    if (segment == null) return null;
    return (kind: segment.kind, top: segment.topOf(index), layer: segment.layer);
  }

  /// [index] 在过渡进度 [progress] 处的不透明度；未被锁定时返回 `null`。
  double? opacityAt(int index, double progress) =>
      _segmentOf(index)?.opacityAt(progress);

  @override
  String toString() => 'FolderZoomItemPinning($_segments)';
}

/// 一段连续的锁定条目（同一种处置、同一档位层、同一个淡入淡出起点）。
@immutable
class _PinSegment {
  const _PinSegment({
    required this.first,
    required this.last,
    required this.kind,
    required this.layer,
    required this.tops,
    required this.opacityFrom,
  });

  final int first;
  final int last;
  final FolderZoomItemPin kind;
  final FolderZoomGeometryLayer layer;

  /// 各条目锁定的屏幕顶部 y，长度等于 `last - first + 1`。
  final Float64List tops;

  /// 过渡起点处的不透明度。
  ///
  /// 正常起手是 `1.0`（淡出）或 `0.0`（淡入）；连点两档时沿用上一段过渡
  /// 当时的不透明度，避免重新冻结时整体闪一下。
  final double opacityFrom;

  double get opacityTo =>
      kind == FolderZoomItemPin.fadeOut ? 0.0 : 1.0;

  double opacityAt(double progress) =>
      opacityFrom + (opacityTo - opacityFrom) * progress.clamp(0.0, 1.0);

  double topOf(int index) {
    final local = index - first;
    if (local < 0 || local >= tops.length) return 0.0;
    return tops[local];
  }

  @override
  String toString() =>
      '${kind.name}[$first..$last]/${layer.isGrid ? 'g' : 'l'}x${layer.crossAxisCount}';
}

/// 单个条目在档位切换过渡期间的呈现方式。
///
/// [isShared] 为 `true` 时按各档位几何加权位移；为 `false` 时条目锁在所属档位的
/// 屏幕位置上，用 [opacity] / [scale] 原地淡入或淡出。
@immutable
class FolderZoomItemTransition {
  const FolderZoomItemTransition({
    required this.isShared,
    required this.opacity,
    required this.scale,
    required this.effectiveMetrics,
  });

  /// 是否走"按权重位移"的混合路径。
  final bool isShared;

  /// 条目整体不透明度。
  final double opacity;

  /// 条目整体缩放比例。
  final double scale;

  /// 条目内部排版使用的度量。
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

  /// 换档时焦点所在的视口高度比例（`0.5` = 视口中心，捏合时为双指中点）。
  final double focusFraction;

  /// 本次过渡开始时冻结的"单侧可见条目"处置表。
  ///
  /// 为 `null` 时表示没有任何条目需要原地淡入淡出，全部按加权位移处理。
  final FolderZoomItemPinning? itemPinning;

  /// 本次过渡的线性进度（`0.0` → `1.0`），单侧条目的淡入淡出按它算不透明度。
  final double transitionProgress;

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
    this.focusFraction = kFolderZoomFocusCenter,
    this.itemPinning,
    this.transitionProgress = 0.0,
  });

  /// 解析指定 [index] 在当前帧的过渡状态。
  ///
  /// 分两路：
  /// - 起始 / 目标档位**都可见**的条目（绝大多数）走加权位移，位置由
  ///   [geometryLayers] 的混合给出（见 `_SliverAnimatedZoomGridLayout
  ///   .getGeometryForChildIndex`），不透明、不缩放。
  /// - 只有一侧可见的条目位置被 [itemPinning] 锁死在该档位的屏幕位置上（布局侧
  ///   不再移动它），这里只负责给出淡入 / 淡出的不透明度与缩放。
  ///
  /// 分类结果在过渡开始时冻结，逐帧不会翻转 —— 这是"原地淡入淡出"能站住的前提，
  /// 细节见 [FolderZoomItemPinning]。
  FolderZoomItemTransition resolveItemTransition(int index) {
    final FolderZoomItemPin pin =
        itemPinning?.pinOf(index) ?? FolderZoomItemPin.shared;
    if (pin == FolderZoomItemPin.shared) {
      return FolderZoomItemTransition(
        isShared: true,
        opacity: 1.0,
        scale: 1.0,
        effectiveMetrics: this,
      );
    }
    final double t = transitionProgress.clamp(0.0, 1.0);
    final double visible =
        itemPinning?.opacityAt(index, t) ?? (pin == FolderZoomItemPin.fadeOut ? 1.0 - t : t);
    return FolderZoomItemTransition(
      isShared: false,
      opacity: visible,
      scale: 1.0 - kFolderZoomFadeScaleDelta * (1.0 - visible),
      effectiveMetrics:
          (pin == FolderZoomItemPin.fadeOut ? startEndpointMetrics : targetEndpointMetrics) ??
              this,
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
    this.controller,
  });

  final double zoomScale;
  final double width;
  final Widget Function(BuildContext context, FolderZoomLayoutMetrics metrics)
      builder;

  /// 滚动控制器：用于在换档时换算并补偿滚动距离。
  ///
  /// 不传时会自动从子树里的 [ScrollView] 找到对应的 [ScrollPosition]；
  /// 一个 [FolderZoomSliverBuilder] 下有多个滚动视图时请显式传入。
  final ScrollController? controller;

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

  /// 本次过渡开始时冻结的"单侧可见条目"处置表。
  ///
  /// 只在 [animate] 换档时生成一次，整段过渡复用（原因见 [FolderZoomItemPinning]）。
  /// 过渡结束 / 转入捏合时清空，避免下一段过渡沿用上一段的位置。
  FolderZoomItemPinning? _itemPinning;

  FolderZoomPinchController? _activePinchController;
  bool _pinchAnchorInitialized = false;
  double _pinchBasePixels = 0.0;
  double _pinchBaseSliverOffset = 0.0;
  double _pinchTargetPixels = 0.0;

  /// 当前 [_pinchTargetPixels] 是按哪个目标档位算出来的。
  ///
  /// 捏合方向要等第一次 `updatePinch()` 才知道，中途还可能反向，所以目标滚动
  /// 位置必须随目标档位变化重算，不能在手势开始那一帧定死。
  double? _pinchTargetScale;

  /// 捏合路径的"单侧可见条目"冻结表，与 [_itemPinning] 同一套机制。
  ///
  /// 捏合的进度由手指驱动、方向还可能中途反转，所以不能像点击换档那样在
  /// `_applyTargets` 里算一次：这里按 `(起始档位, 目标档位)` 缓存，方向确定的那一帧
  /// 冻结一次；目标反转时重算 —— 反转只可能发生在双指间距跨过手势起点
  /// （`progress ≈ 0`）的那一帧，此刻两层几何的权重正好是 `(1, 0)`，重算等价于
  /// 重新按起始档位判定，不会有条目从锁定位置瞬移。
  FolderZoomItemPinning? _pinchPinning;
  double? _pinchPinningFrom;
  double? _pinchPinningTo;
  bool _pinchPinningReady = false;

  /// 缓存的滚动位置，用于免去每帧重新在渲染树里找 viewport。
  ScrollPosition? _cachedPosition;

  /// [_cachedPosition] 是从哪个 viewport 上取的。
  ///
  /// [Scrollable] 的 `didChangeDependencies` 会 `_updatePosition()`：老位置被
  /// `dispose`，新位置顶上，而**两者共用同一个 [ScrollContext]**（`mounted` 依旧
  /// 为 true），老位置的 `pixels` 从此冻结。只靠"缓存是否 mounted"抓不住这种僵尸，
  /// 但 `viewport.offset` 一定会指向新位置，所以用 `identical` 比一下就是 O(1) 的
  /// 存活校验。
  RenderViewportBase? _cachedViewport;

  /// 本帧/本次过渡里还允许几次"丢掉缓存重新找"，避免每帧遍历渲染树。
  int _selfHealBudget = 3;

  /// 过渡动画的计时器，只用于日志里把帧与真实时间对上。
  final Stopwatch _animWatch = Stopwatch();

  /// 上一次打过日志的滚动位置，避免 `_scrollPosition()` 每帧刷屏。
  ScrollPosition? _loggedPosition;

  /// 上一次由本类写入的滚动像素值，用于发现"两帧之间被别处改过"。
  double? _lastWrittenPixels;

  /// 取本次换档要操作的滚动位置。
  ///
  /// [FolderZoomSliverBuilder] 的 context 在 [CustomScrollView] **之上**，
  /// 所以 `Scrollable.maybeOf(context)` 永远拿不到它（祖先链上没有 Scrollable）。
  /// 这里改成：显式传入的 controller > 从渲染树里找到的 viewport offset。
  ///
  /// 渲染树里可能不止一个纵向 viewport（嵌套滚动、`IndexedStack` 里留着的旧页面等），
  /// 盲取第一个会挑到"幽灵"位置：它自己不跟手，只有我们往里写像素值，于是每次
  /// 换档的滚动补偿都打在它身上，几何层的 `correction` 只能把内容顶回去 ——
  /// 屏幕上就是列表在切档时快速上下甩一截再弹回。所以这里**必须拿布局真实值校验**。
  ScrollPosition? _scrollPosition() {
    final controller = widget.controller;
    if (controller != null) {
      final position = controller.hasClients ? controller.position : null;
      _logPosition('controller', position);
      return position;
    }

    final cached = _cachedPosition;
    if (cached != null && _isLivePosition(cached)) {
      if (_isAlignedWithLayout(cached)) {
        _selfHealBudget = 3;
        return cached;
      }
      // 对不上就丢掉缓存重新挑，别让一个错的位置一直用下去。
      // 但重挑本身要在渲染树里遍历，给个预算避免每帧都扫一遍。
      if (_selfHealBudget > 0) {
        _selfHealBudget--;
        _cachedPosition = null;
        _cachedViewport = null;
        _logPosition('selfHeal', null);
      } else {
        return cached;
      }
    }

    final candidates = _collectViewports(context.findRenderObject());
    final viewport = _selectAligned(candidates);
    final position = viewport?.offset;
    _cachedViewport = position is ScrollPosition ? viewport : null;
    _cachedPosition = position is ScrollPosition ? position : null;
    _logPosition('renderTree', _cachedPosition);
    return _cachedPosition;
  }

  /// [position] 是否仍然是**当前**驱动布局的那个滚动位置。
  ///
  /// 安卓上 MediaQuery（系统栏 / 刘海 insets）在启动后还会再变一次，触发
  /// [Scrollable] 的 `_updatePosition()` 换掉位置对象；缓存里留着旧的那个，
  /// 它的 `pixels` 会永远停在换掉那一刻的值（通常是 `0.0`）。之后所有
  /// "sliver 坐标 ↔ 滚动像素"的换算都会崩：目标像素算成负数被夹到 0，
  /// 过渡期滚动补偿全部失效，条目只能跟着几何层一起滑动 —— 也就是
  /// "所有条目都发生位移动画"。macOS 窗口尺寸一帧就稳定，碰不到这条路径。
  bool _isLivePosition(ScrollPosition position) {
    if (!position.hasPixels) return false;
    final viewport = _cachedViewport;
    if (viewport != null) return identical(viewport.offset, position);
    return position.context.notificationContext?.mounted ?? false;
  }

  /// [position] 是否能解释当前布局：`pixels - scrollOffset` 就是该 sliver 之前的
  /// 滚动内容长度，必然 `>= 0`（`SliverPadding` 之类给的是个很小的正数）。
  /// 明显为负说明这个位置根本不是布局本 sliver 的那个。
  bool _isAlignedWithLayout(ScrollPosition position) {
    if (!_viewportTracker.hasMeasurement) return true;
    if (!position.hasPixels) return false;
    return position.pixels - _viewportTracker.viewportTop >= -1.0;
  }

  /// 在候选里挑最可能是"布局本 sliver"的那个。
  ///
  /// 判据同上：`pixels - scrollOffset >= 0` 且越接近越好（前置滚动内容通常很小）。
  /// 全都对不上时退回第一个，保持旧行为。
  ///
  /// 返回的是 viewport 而不是裸的 [ScrollPosition]：位置对象会被 [Scrollable] 中途
  /// 换掉（见 [_isLivePosition]），而 viewport 是稳定的，留着它才能在下一帧用
  /// `identical(viewport.offset, position)` 判断缓存还活着没有。
  RenderViewportBase? _selectAligned(List<RenderViewportBase> candidates) {
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first;
    RenderViewportBase? best;
    double bestPrecede = double.infinity;
    for (final candidate in candidates) {
      final offset = candidate.offset;
      if (offset is! ScrollPosition || !offset.hasPixels) continue;
      final double precede = offset.pixels - _viewportTracker.viewportTop;
      if (precede < -1.0) continue;
      if (precede < bestPrecede) {
        bestPrecede = precede;
        best = candidate;
      }
    }
    zoomLog('select', () {
      final bestOffset = best?.offset;
      return 'candidates=${candidates.length} '
          'chosen=#${identityHashCode(bestOffset)} '
          'precede=${zd(best == null ? null : bestPrecede)} '
          '${candidates.map((c) {
            final offset = c.offset;
            return '#${identityHashCode(offset)}/${zd(offset is ScrollPosition ? _pixelsOf(offset) : null)}';
          }).join(',')}';
    });
    return best ?? candidates.first;
  }

  void _logPosition(String via, ScrollPosition? position) {
    if (!folderZoomDebugLog || identical(position, _loggedPosition)) return;
    _loggedPosition = position;
    zoomLog('pos', () {
      return 'via=$via pos=${position == null ? 'null' : position.runtimeType} '
          'px=${zd(_pixelsOf(position))} max=${zd(_maxExtentOf(position))} '
          'clients=${widget.controller?.hasClients ?? '-'}';
    });
  }

  /// 安全读取像素值：首帧布局时 `ScrollPosition` 可能还没有内容尺寸。
  static double? _pixelsOf(ScrollPosition? position) =>
      (position != null && position.hasPixels) ? position.pixels : null;

  /// 安全读取最大滚动偏移；首次布局时 `_maxScrollExtent` 仍为 null，直接读会抛空。
  static double? _maxExtentOf(ScrollPosition? position) =>
      (position != null && position.hasContentDimensions)
          ? position.maxScrollExtent
          : null;

  /// 在渲染树里收集所有可能属于本 sliver 的 viewport。
  ///
  /// 两种常见用法方向相反，都要覆盖：
  /// - [FolderZoomSliverBuilder] 被放进 `CustomScrollView.slivers` 里（多数页面如此）：
  ///   它的 renderObject 就是一个 sliver，viewport 在**祖先**方向；
  /// - 它包住整个 `CustomScrollView`（README 的写法）：viewport 在**后代**里。
  ///
  /// 以前只朝后代遍历，前一种用法恒返回 `null`，滚动补偿静默失效——表现为
  /// 中段/底部换档时内容原地跳变而不是跟着焦点平移。
  ///
  /// 现在返回**全部**候选而不是第一个：多 viewport 时由 [_selectAligned] 用布局
  /// 真实值挑，避免盲取到不跟手的幽灵位置。
  static List<RenderViewportBase> _collectViewports(RenderObject? root) {
    if (root == null) return const <RenderViewportBase>[];

    if (folderZoomDebugLog) _scanViewportsForLog(root);

    final List<RenderViewportBase> result = <RenderViewportBase>[];

    if (root is RenderSliver) {
      RenderObject? node = root.parent;
      while (node != null) {
        if (node is RenderViewportBase && !result.contains(node)) {
          result.add(node);
        }
        final parent = node.parent;
        node = parent is RenderObject ? parent : null;
      }
      return result;
    }

    void visit(RenderObject node) {
      if (node is RenderViewportBase && !result.contains(node)) {
        result.add(node);
      }
      node.visitChildren(visit);
    }

    visit(root);
    return result;
  }

  /// 调试用：把子树里所有 [RenderViewportBase] 列出来。
  ///
  /// 一次换档里出现两条互不相干的 `pixels` 序列（`top` 与 `px` 对不上）时，
  /// 十之八九是这里找到了不止一个 viewport，而 `_scrollPosition()` 挑错了那个。
  static void _scanViewportsForLog(RenderObject root) {
    final List<String> seen = <String>[];
    void scan(RenderObject node) {
      if (node is RenderViewportBase) {
        final offset = node.offset;
        if (offset is ScrollPosition) {
          seen.add('vp#${identityHashCode(node)}'
              '/${node.axisDirection.name}'
              '/pos#${identityHashCode(offset)}'
              '/px=${zd(offset.hasPixels ? offset.pixels : null)}'
              '/max=${zd(offset.hasContentDimensions ? offset.maxScrollExtent : null)}');
        }
      }
      node.visitChildren(scan);
    }

    scan(root);
    zoomLog('find', () {
      return 'root=${root.runtimeType} viewports=${seen.length} '
          '${seen.join(' | ')}';
    });
  }

  /// 当前滚动像素值；布局期由 [FolderZoomViewportTracker] 回填，用于把
  /// "sliver 坐标"和"滚动像素"对齐到同一时刻。
  double _currentScrollPixels() {
    final position = _scrollPosition();
    return (position != null && position.hasPixels) ? position.pixels : 0.0;
  }

  @override
  void initState() {
    super.initState();
    _viewportTracker.scrollPixelsReader = _currentScrollPixels;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )
      ..addListener(_onTick)
      ..addStatusListener(_onAnimationStatusChanged);
    _curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  void _onTick() {
    if (!mounted) return;
    if (_controller.isAnimating) {
      _syncScrollToProgress(_curved.value);
    }
    setState(() {});
  }

  /// 过渡结束的那一帧必须补上，否则滚动位置永远差最后一段距离。
  ///
  /// `AnimationController` 在最后一个 tick 里会先 `stop()` 再 `notifyListeners()`，
  /// 于是 `_onTick` 里 `isAnimating` 已经是 false，最后一步会被丢掉（实测触底换档
  /// 会停在离底部十几像素处，且残差随帧率变化）。所以终帧单独挂在状态监听上。
  void _onAnimationStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    _syncScrollToProgress(1.0);
  }

  /// 把滚动位置推到 [progress] 对应的插值位置。
  void _syncScrollToProgress(double progress) {
    if ((_startScrollPixels - _targetScrollPixels).abs() <= 0.5) {
      zoomLog('tick', () {
        return 't=${zd(progress, 3)} skip: no scroll delta '
            '(start=${zd(_startScrollPixels)})';
      });
      return;
    }
    final position = _scrollPosition();
    if (position == null ||
        !position.hasPixels ||
        !_viewportTracker.isActiveInViewport) {
      zoomLog('tick', () {
        return 't=${zd(progress, 3)} skip: pos=${position != null} '
            'hasPixels=${position?.hasPixels} '
            'active=${_viewportTracker.isActiveInViewport} '
            'remain=${zd(_viewportTracker.remainingPaintExtent)}';
      });
      return;
    }
    final target =
        lerpDouble(_startScrollPixels, _targetScrollPixels, progress)!;
    // 不按 `position.maxScrollExtent` 夹取：过渡期的最大偏移每帧都在变，
    // 而这里拿到的是上一帧布局算出来的值。内容正在变长时（触底换档最常见），
    // 用它夹取会让滚动永远慢一帧 —— 条目被画低上千像素，下一帧再被拽回来，
    // 屏幕上就是"所有条目从下往上弹一下"。越界交给本次布局的
    // `applyContentDimensions` 用当前帧的最大偏移纠正。
    final clamped = math.max(0.0, target);
    final double before = position.pixels;
    final bool willJump = (before - clamped).abs() > 0.5;

    // 上一次写进去的像素值：若这次读到的和它对不上，说明两帧之间有人动过滚动
    // 位置（边界修正 / 弹道模拟 / 用户拖动）。安卓上"列表上下抖"就是这里来的。
    final double? expected = _lastWrittenPixels;
    final bool movedBetweenTicks =
        expected != null && (before - expected).abs() > 0.5;

    if (willJump) {
      position.jumpTo(clamped);
      _lastWrittenPixels = position.pixels;
    }
    zoomLog('tick', () {
      return 't=${zd(progress, 3)} '
          'ms=${_animWatch.elapsedMilliseconds} '
          'want=${zd(target)} clamped=${zd(clamped)} '
          'px=${zd(before)} -> ${zd(position.pixels)} '
          'jump=${willJump ? zd(position.pixels - before) : 'no'} '
          '${movedBetweenTicks ? 'EXTERNAL drift=${zd(before - expected)} ' : ''}'
          'max=${zd(_maxExtentOf(position))} '
          'top=${zd(_viewportTracker.viewportTop)} '
          'mix=${_viewportTracker.anchorEdgeName}';
    });
  }

  void _onPinchChanged() {
    final pinch = _activePinchController;
    if (!mounted || pinch == null) return;
    if (!pinch.isActive) {
      _pinchAnchorInitialized = false;
      _pinchTargetScale = null;
      _resetPinchPinning();
      return;
    }
    final position = _scrollPosition();
    if (position == null ||
        !position.hasPixels ||
        !_viewportTracker.isActiveInViewport) {
      return;
    }

    final isPortrait =
        MediaQuery.maybeOrientationOf(context) == Orientation.portrait;

    if (!_pinchAnchorInitialized) {
      // 按双指中点重新取锚，手指下的内容在捏合过程中才不会跟着漂。
      final double? focus = _focusFractionAt(pinch.focalGlobal, position);
      _viewportTracker.refreshAnchor(
        focusFraction: focus ?? kFolderZoomFocusCenter,
        isPortrait: isPortrait,
      );
      _pinchBasePixels = position.pixels;
      _pinchBaseSliverOffset = _sliverTopForPixels(position.pixels);
      _pinchAnchorInitialized = true;
      _pinchTargetScale = null;
      zoomLog('pinch', () {
        return 'begin base=${zd(pinch.baseZoomScale, 3)} '
            'px=${zd(_pinchBasePixels)} sliver=${zd(_pinchBaseSliverOffset)} '
            'focus=${zd(focus)} '
            'anchor=${_viewportTracker.anchorEdgeName}'
            '#${_viewportTracker.anchorIndex} '
            'r=${zd(_viewportTracker.anchorRatio, 3)} '
            'f=${zd(_viewportTracker.anchorFocusY)} '
            'top=${zd(_viewportTracker.viewportTop)} '
            'vh=${zd(_viewportTracker.viewportHeight)}';
      });
    }

    // 目标档位变了才重算目标滚动位置。
    //
    // `startPinch()` 自己会 notify 一次，那时 `updatePinch()` 还没跑过，
    // `targetZoomScale` 仍然等于基准档位。早期实现就在这一帧把目标锁死了：
    // 锚定目标 == 起点，整段捏合期间滚动一动不动，而几何层却在向目标档位插值，
    // 屏幕上的条目于是被甩出上千像素（安卓真机上就是"换档时列表快速上下移动"）。
    // 现在改成"方向确定后才求解"，并在中途反向时按同一基准重算。
    if (_pinchTargetScale == null ||
        (pinch.targetZoomScale - _pinchTargetScale!).abs() > 1e-4) {
      final toTargets = _calculateTargets(
        pinch.targetZoomScale,
        isPortrait: isPortrait,
      );
      final targetLayer = _layerOf(toTargets, 1.0);
      final targetTop = _viewportTracker.solveViewportTopFor(
        targetLayer,
        isPortrait: isPortrait,
      );
      // 上界**不夹取**，与点击档位那条路（`_applyTargets`）保持完全一致。
      //
      // 曾经这里按目标档位的 `maxScrollOffsetFor()` 夹取，那是个**单位错误**：
      // `maxScrollOffsetFor()` 返回的是 sliver 坐标（`内容总高 - 视口高`，且不含
      // 外层 `SliverPadding`），而 `_pinchTargetPixels` 是滚动像素 —— 两者相差
      // 一个 `precede`（上方 padding / header 的高度）加上尾部 padding。于是只要
      // 滚到列表底部，捏合的目标就被少算 `precede + 尾部 padding` 那么多：
      // 点击换档精确贴底，捏合却停在离底还差一截的位置，整片内容偏下、最后一行
      // 被切掉。header 越高偏得越多（实测 32px 到 400px 以上）。
      //
      // 越界交给本次布局的 `applyContentDimensions` 纠正，和点击路径同款处理。
      _pinchTargetPixels = math.max(
        0.0,
        _pinchBasePixels + (targetTop - _pinchBaseSliverOffset),
      );
      _pinchTargetScale = pinch.targetZoomScale;
      zoomLog('pinch', () {
        return 'solve target=${zd(pinch.targetZoomScale, 3)} '
            'base=${zd(_pinchBasePixels)} '
            'baseSliver=${zd(_pinchBaseSliverOffset)} '
            'targetTop=${zd(targetTop)} '
            'targetPx=${zd(_pinchTargetPixels)} '
            'maxTarget=${zd(_viewportTracker.maxScrollOffsetFor(targetLayer, isPortrait: isPortrait))} '
            'maxCur=${zd(_maxExtentOf(position))} '
            'anchor=${_viewportTracker.anchorEdgeName}'
            '#${_viewportTracker.anchorIndex} '
            'r=${zd(_viewportTracker.anchorRatio, 3)} '
            'f=${zd(_viewportTracker.anchorFocusY)} '
            'layer=${FolderZoomViewportTracker._layerTag(targetLayer)}';
      });
    }

    final targetPixels = lerpDouble(
      _pinchBasePixels,
      _pinchTargetPixels,
      pinch.progress,
    )!;
    final double before = position.pixels;
    if ((before - targetPixels).abs() > 0.5) {
      position.jumpTo(targetPixels);
    }
    zoomLog('pinch', () {
      return 't=${zd(pinch.progress, 3)} '
          'target=${zd(pinch.targetZoomScale, 3)} '
          'px=${zd(before)} -> ${zd(position.pixels)} '
          'want=${zd(targetPixels)} '
          'top=${zd(_viewportTracker.viewportTop)}';
    });
  }

  /// 当前像素对应的 sliver 顶部偏移。
  ///
  /// [FolderZoomViewportTracker.viewportTop] 是**上一次布局**记下的 sliver 顶部，
  /// 而换档发生在两帧之间，此时滚动像素可能已经前进了一整帧。直接拿两者相减会
  /// 把目标偏移算高一个帧的滚动量（实测触底连点两档多算 290px，滚动越界后再靠
  /// 回弹模拟弹回来）。这里改用"上次布局时的像素 → sliver 顶部"的固定差值换算，
  /// 保证起点的像素与 sliver 坐标取在同一时刻。
  double _sliverTopForPixels(double pixels) {
    final double? layoutPixels = _viewportTracker.pixelsAtLayout;
    if (layoutPixels == null) return _viewportTracker.viewportTop;
    return pixels + (_viewportTracker.viewportTop - layoutPixels);
  }

  /// 把手势焦点的全局坐标换算成视口内的高度比例。
  double? _focusFractionAt(Offset? global, ScrollPosition position) {
    if (global == null) return null;
    final box = position.context.storageContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.height <= 1.0) {
      return null;
    }
    final local = box.globalToLocal(global);
    return (local.dy / box.size.height).clamp(0.0, 1.0);
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
    if (layers.length == 1) {
      // 动画还在跑却只剩一层：此时 `SliverAnimatedZoomGridDelegate` 会把
      // `isAnimating` 传成 false，tracker 于是重新取锚并把 correction 清零，
      // 过渡中途被"重新锚定"就会看见视图整体跳一下。
      zoomLog('layers', () {
        return 'WARN animating but single layer @t=${zd(p, 3)} '
            'from=${_geometryFrom.length} '
            'wk=${_geometryFrom.map((e) => e.weight.toStringAsFixed(3)).join('/')}';
      });
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

  void _resetPinchPinning() {
    _pinchPinning = null;
    _pinchPinningFrom = null;
    _pinchPinningTo = null;
    _pinchPinningReady = false;
  }

  /// 取本次捏合要用的"单侧可见条目"冻结表；方向未判定时返回 `null`。
  ///
  /// 少了它，捏合全程只能走"所有条目按两端几何加权位移"这一条路：只在起始档位
  /// 可见的条目也会跟着插值上下漂，屏幕上就是「双指一捏，整屏条目一起移动」。
  /// 点击换档之所以没有这个现象，是因为它走 [_applyTargets] 那条路，里面有
  /// [FolderZoomViewportTracker.buildPinning] 把单侧条目锁在原地淡入淡出。
  FolderZoomItemPinning? _resolvePinchPinning({
    required _ZoomTargets targetsFrom,
    required _ZoomTargets targetsTo,
    required bool isPortrait,
  }) {
    final double from = targetsFrom.zoomScale;
    final double to = targetsTo.zoomScale;

    // 方向还没确定（目标 == 起始）：进度恒为 0，两层几何权重是 (1, 0)，
    // 所有条目本来就落在起始档位的位置上，不需要冻结。
    if ((to - from).abs() <= 1e-4) {
      _resetPinchPinning();
      return null;
    }
    if (_pinchPinningReady &&
        _pinchPinningFrom == from &&
        _pinchPinningTo == to) {
      return _pinchPinning;
    }

    // `mixLayers` 用**此刻屏幕上真实生效**的几何层：从点击换档的过渡动画中途
    // 接管时它就是那段动画的混合结果，锁在原位的参照系才是上一帧画出来的位置。
    final targetLayer = _layerOf(targetsTo, 1.0);
    _pinchPinning = _viewportTracker.buildPinning(
      mixLayers: _effectiveGeometryLayers(_curved.value),
      targetLayer: targetLayer,
      // 与布局侧 `_layerViewportTop(targetLayer)` 同一口径，淡入条目的锁定位置
      // 在 `progress = 0` 处才与目标位置严格相等，不会出现起步一帧的位移。
      targetViewportTop: _viewportTracker.viewportTopForLayer(
        targetLayer,
        isPortrait: isPortrait,
      ),
      isPortrait: isPortrait,
    );
    _pinchPinningFrom = from;
    _pinchPinningTo = to;
    _pinchPinningReady = true;
    zoomLog('pinch', () {
      final pinning = _pinchPinning;
      final String segments = pinning == null || pinning.isEmpty
          ? 'none'
          : '${pinning.firstPinnedIndex}..${pinning.lastPinnedIndex}';
      return 'pinning ${zd(from, 3)} -> ${zd(to, 3)} segments=$segments';
    });
    return _pinchPinning;
  }

  void _applyTargets(_ZoomTargets targets, {required bool animate}) {
    _targetCardWidth = targets.cardWidth;

    if (animate) {
      _selfHealBudget = 3;
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
      final double targetSliverOffset = _viewportTracker.solveViewportTopFor(
        targetLayer,
        isPortrait: isPortrait,
      );

      final position = _scrollPosition();
      if (position != null &&
          position.hasPixels &&
          _viewportTracker.isActiveInViewport) {
        final currentPixels = position.pixels;
        _startSliverOffset = _sliverTopForPixels(currentPixels);
        _targetSliverOffset = targetSliverOffset;
        _startScrollPixels = currentPixels;
        _targetScrollPixels =
            currentPixels + (_targetSliverOffset - _startSliverOffset);
      } else {
        _startSliverOffset = _viewportTracker.viewportTop;
        _targetSliverOffset = targetSliverOffset;
        _startScrollPixels = 0.0;
        _targetScrollPixels = 0.0;
      }

      final tracker = _viewportTracker;

      // 冻结"哪些条目原地淡入淡出"。必须在这里算：`_collapseGeometry` 刚把
      // `_geometryFrom` 折成**当前屏幕上实际生效**的混合层，用它算出的屏幕位置
      // 就是上一帧画出来的位置，连点两档也不会让被锁定的条目瞬移。
      //
      // 上一段过渡还在跑（`_controller.isAnimating`）时把旧表带进来：已经被锁定
      // 的条目已经在"不跟几何走"的位置上，重新按混合几何判定会让它跳一截。
      final previousPinning = _controller.isAnimating ? _itemPinning : null;
      _itemPinning = tracker.buildPinning(
        mixLayers: <FolderZoomGeometryLayer>[
          for (final entry in _geometryFrom)
            _layerOf(entry.targets, entry.weight),
        ],
        targetLayer: targetLayer,
        targetViewportTop: targetSliverOffset,
        isPortrait: isPortrait,
        previous: previousPinning,
        previousProgress: _curved.value,
      );

      // 过渡起始时记下这一帧的全部输入：安卓真机上的"快速上下移动"如果来自
      // 求解出的目标与真实布局不一致，这里会直接暴露出来。
      zoomLog('switch', () {
        return 'animate ${zd(_fromZoomScale, 3)} -> ${zd(widget.zoomScale, 3)} '
            '${isPortrait ? 'portrait' : 'landscape'} w=${zd(widget.width)} '
            'root=${context.findRenderObject()?.runtimeType} '
            'meta=${MediaQuery.maybeSizeOf(context)} '
            'textScale=${zd(folderZoomTextScaleOf(context), 2)} '
            'pos=${position != null && position.hasPixels ? 'ok' : 'none'} '
            'px=${zd(_startScrollPixels)} '
            'startSliver=${zd(_startSliverOffset)} '
            'targetSliver=${zd(_targetSliverOffset)} '
            'targetPx=${zd(_targetScrollPixels)} '
            'maxCur=${zd(_maxExtentOf(position))} '
            'maxTarget=${zd(tracker.maxScrollOffsetFor(targetLayer, isPortrait: isPortrait))} '
            'posId=#${identityHashCode(position)} '
            'precede=${zd(tracker.pixelsAtLayout == null ? null : tracker.pixelsAtLayout! - tracker.viewportTop)} '
            'top=${zd(tracker.viewportTop)} vh=${zd(tracker.viewportHeight)} '
            'active=${tracker.isActiveInViewport} '
            'anchor=${tracker.anchorEdgeName}#${tracker.anchorIndex} '
            'r=${zd(tracker.anchorRatio, 3)} f=${zd(tracker.anchorFocusY)} '
            'physics=${position?.physics.runtimeType} '
            'layers=${FolderZoomViewportTracker._layerTag(targetLayer)}';
      });
      _animWatch
        ..reset()
        ..start();
      _lastWrittenPixels = null;
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
      _itemPinning = null;
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
    if (!_loggedEnv && folderZoomDebugLog) {
      _loggedEnv = true;
      zoomLog('env', () {
        return 'platform=$defaultTargetPlatform '
            'size=${MediaQuery.maybeSizeOf(context)} '
            'dpr=${MediaQuery.maybeDevicePixelRatioOf(context)} '
            'textScale=${zd(folderZoomTextScaleOf(context), 2)} '
            'portrait=${MediaQuery.maybeOrientationOf(context) == Orientation.portrait} '
            'zoom=${zd(widget.zoomScale, 3)} w=${zd(widget.width)}';
      });
    }
  }

  bool _loggedEnv = false;

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
      final bool pinchHandoff = pinch != null &&
          pinch.committedScale != null &&
          (pinch.committedScale! - widget.zoomScale).abs() < 1e-4;
      zoomLog('didUpdate', () {
        return 'scale ${zd(oldWidget.zoomScale, 3)} -> ${zd(widget.zoomScale, 3)} '
            'pinch=${pinch != null} committed=${zd(pinch?.committedScale, 3)} '
            'animate=${!pinchHandoff} '
            'pos=${zd(_currentScrollPixels())} '
            'top=${zd(_viewportTracker.viewportTop)}';
      });
      if (pinchHandoff) {
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
        itemPinning: _resolvePinchPinning(
          targetsFrom: targetsFrom,
          targetsTo: targetsTo,
          isPortrait: isPortrait,
        ),
        transitionProgress: t,
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
      // 过渡结束（只剩单层）后不再需要冻结表：此时所有条目都已在终态位置上。
      itemPinning: _controller.isAnimating ? _itemPinning : null,
      transitionProgress: progress,
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

    // 视口顶端在 sliver 坐标系里的位置。
    //
    // 不能直接用 `constraints.scrollOffset`：当这个 sliver 的起始边还在视口顶端
    // **之下**（上方还有别的 sliver / `SliverPadding`，页面还没滚到列表），Flutter
    // 会把 `scrollOffset` 钳在 0（`RenderViewportBase.layoutChildSequence` 里
    // `scrollOffset <= 0 ? 0 : scrollOffset`），真实的负值被吃掉。此时"起始边到
    // 视口顶端的距离"只能从剩余绘制长度反推：
    //
    //   remainingPaintExtent == 视口主轴向长度 - 起始边到视口顶端的距离
    //
    // 少了这一步，`viewportTop` 恒为 0，锚定会把这种情况误判成"列表已贴顶"，
    // 换档 / 捏合时直接跳过滚动补偿（内容只在原地往下长）。
    final double leadingGap = math.max(
      0.0,
      constraints.viewportMainAxisExtent - constraints.remainingPaintExtent,
    );
    final double viewportTop = constraints.scrollOffset - leadingGap;
    // 视口底端 = 顶端 + 视口主轴向长度（`viewportHeight` 必须是**视口高**，
    // 而不是 `remainingPaintExtent`：后者已经被上方的 header 吃掉一截）。
    final double viewportBottom =
        viewportTop + constraints.viewportMainAxisExtent;
    final layers = metrics.resolvedGeometryLayers;
    final tracker = metrics.viewportTracker;
    if (tracker != null) {
      tracker.record(
        usableWidth: usableWidth,
        outerWidth: metrics.outerWidth,
        viewportTop: viewportTop,
        viewportBottom: viewportBottom,
        remainingPaintExtent: constraints.remainingPaintExtent,
        layers: layers,
        isAnimating: layers.length > 1,
        isPortrait: metrics.isPortrait,
        focusFraction: metrics.focusFraction,
        listMainAxisSpacing: listMainAxisSpacing,
        gridCrossAxisSpacing: gridCrossAxisSpacing,
        gridMainAxisSpacing: gridMainAxisSpacing,
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
      pinning: layers.length > 1 ? metrics.itemPinning : null,
      progress: metrics.transitionProgress,
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
    this.pinning,
    this.progress = 0.0,
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

  /// 过渡开始时冻结的单侧可见条目处置表；见 [FolderZoomItemPinning]。
  final FolderZoomItemPinning? pinning;

  /// 本次过渡的线性进度，被锁定条目的收敛用。
  final double progress;

  bool get _hasSingleLayer => layers.length == 1;

  double _layerViewportTop(FolderZoomGeometryLayer layer) {
    if (tracker == null || !tracker!.hasMeasurement) return viewportTop;
    return tracker!.viewportTopForLayer(layer, isPortrait: isPortrait);
  }

  double get _viewportHeight {
    if (tracker != null && tracker!.hasMeasurement) {
      return tracker!.viewportHeight;
    }
    return math.max(0.0, viewportBottom - viewportTop);
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

    // 只有一侧档位可见的条目：位置锁在过渡开始那一刻的屏幕位置上，配合
    // `resolveItemTransition` 给出的不透明度原地淡入 / 淡出。锁定值来自
    // [pinning]，逐帧不变 —— 所以这里不会出现"位置在混合值与锁定值之间瞬移"。
    final pinning = this.pinning;
    if (pinning != null) {
      final info = pinning.pinInfoOf(index);
      if (info != null) {
        if (info.kind == FolderZoomItemPin.fadeOut) {
          final geometry = _geometryIn(info.layer, index);
          return SliverGridGeometry(
            scrollOffset: viewportTop + info.top,
            crossAxisOffset: geometry.crossAxisOffset,
            mainAxisExtent: geometry.mainAxisExtent,
            crossAxisExtent: geometry.crossAxisExtent,
          );
        }
        // 淡入条目原地出现在**目标**位置上：正常换档时冻结值就等于目标位置，
        // 这里是恒等映射；只有连点两档、目标变了的时候才需要从旧锁定位置
        // 平滑挪到新目标位置，避免过渡结束那一帧跳一下。
        final targetLayer = layers.last;
        final targetTop = _geometryIn(targetLayer, index).scrollOffset -
            _layerViewportTop(targetLayer);
        final double top =
            lerpDouble(info.top, targetTop, progress.clamp(0.0, 1.0)) ??
                targetTop;
        final geometry = _geometryIn(targetLayer, index);
        return SliverGridGeometry(
          scrollOffset: viewportTop + top,
          crossAxisOffset: geometry.crossAxisOffset,
          mainAxisExtent: geometry.mainAxisExtent,
          crossAxisExtent: geometry.crossAxisExtent,
        );
      }
    }

    // 过渡期：条目位置 = 各档位下该条目的**屏幕位置**的加权平均。
    //
    // 用「屏幕位置」而不是原始 `scrollOffset` 做平均：各层的视口顶部由焦点锚
    // （含过渡期残差修正）给出，这样换算出的位置在屏幕上是稳定的，不受
    // 过渡期实际滚动量抖动的影响。
    double weight = 0.0;
    double screenTop = 0.0;
    double crossAxisOffset = 0.0;
    double mainAxisExtent = 0.0;
    double crossAxisExtent = 0.0;
    for (final layer in layers) {
      final double layerWeight = layer.weight;
      if (layerWeight <= 0.0) continue;
      final geometry = _geometryIn(layer, index);
      weight += layerWeight;
      screenTop +=
          (geometry.scrollOffset - _layerViewportTop(layer)) * layerWeight;
      crossAxisOffset += geometry.crossAxisOffset * layerWeight;
      mainAxisExtent += geometry.mainAxisExtent * layerWeight;
      crossAxisExtent += geometry.crossAxisExtent * layerWeight;
    }
    if (weight <= 1e-6) {
      return _geometryIn(layers.last, index);
    }
    final double inverse = 1.0 / weight;
    return SliverGridGeometry(
      scrollOffset: viewportTop + screenTop * inverse,
      crossAxisOffset: crossAxisOffset * inverse,
      mainAxisExtent: mainAxisExtent * inverse,
      crossAxisExtent: crossAxisExtent * inverse,
    );
  }

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
    return contentExtentIn(
      layer: layer,
      childCount: childCount,
      usableWidth: usableWidth,
      outerWidth: outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: listMainAxisSpacing,
      gridCrossAxisSpacing: gridCrossAxisSpacing,
      gridMainAxisSpacing: gridMainAxisSpacing,
    );
  }

  /// [layer] 档位下 [childCount] 个条目的内容总高度（不含视口高度）。
  static double contentExtentIn({
    required FolderZoomGeometryLayer layer,
    required int childCount,
    required double usableWidth,
    double outerWidth = 0.0,
    bool isPortrait = false,
    double listMainAxisSpacing = kFolderListRowSpacing,
    double gridCrossAxisSpacing = kGridCrossAxisSpacing,
    double gridMainAxisSpacing = kGridMainAxisSpacing,
  }) {
    if (childCount <= 0) return 0.0;
    final stride = mainStrideFor(
      layer: layer,
      usableWidth: usableWidth,
      outerWidth: outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: listMainAxisSpacing,
      gridCrossAxisSpacing: gridCrossAxisSpacing,
      gridMainAxisSpacing: gridMainAxisSpacing,
    );
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
    // 被锁定的条目位置与所在层视口解耦（见 getGeometryForChildIndex），
    // 索引区间必须一并覆盖，否则它们会因为"算出来在视口外"而不被构建。
    final firstPinned = pinning?.firstPinnedIndex;
    if (firstPinned != null && firstPinned < result) result = firstPinned;
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
    final lastPinned = pinning?.lastPinnedIndex;
    if (lastPinned != null && lastPinned > result) result = lastPinned;
    return result;
  }

  @override
  double computeMaxScrollOffset(int childCount) {
    // 回填条目总数，tracker 才能在换算目标档位的滚动偏移时按各档位的最大偏移夹取。
    tracker?.contentCount = childCount;
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
