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

/// 旧版"单侧可见条目淡入淡出"的缩放幅度。
///
/// 过渡期改为纯几何加权后（见 [FolderZoomLayoutMetrics.resolveItemTransition]），
/// 单侧可见条目不再原地淡入淡出，这个常量已不参与布局。保留仅为兼容性。
@Deprecated('单侧可见条目不再做淡入淡出，此常量已不再参与布局')
const double kFolderZoomFadeScaleDelta = 0.15;

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

  /// **真实**的 Sliver 滚动偏移，每次布局都会刷新（不再冻结）。
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

  /// 当前 Sliver 是否在视口中可见（用于多 Sliver 时仅激活可见 Sliver 的滚动吸附）。
  bool get isActiveInViewport => hasMeasurement && remainingPaintExtent > 10.0;

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
      return;
    }

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
    if (viewportTop <= 0.5) {
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

    final double focus = _resolveFocusY(
      height,
      focusFraction,
      layer: layer,
      isPortrait: isPortrait,
    );
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

    final double topBlend = (1.0 - viewportTop / height).clamp(0.0, 1.0);
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
        return 0.0;
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
    return math.max(0.0, top);
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
}

/// 单个条目在档位切换过渡期间的呈现方式。
///
/// 目前过渡期所有条目都按"共用条目"处理：[isShared] 恒为 `true`，
/// [opacity] / [scale] 恒为 `1.0`，位置由各档位几何的加权混合给出。
/// 保留这三个字段是为了让自定义条目仍然可以按同样方式消费这份描述。
@immutable
class FolderZoomItemTransition {
  const FolderZoomItemTransition({
    required this.isShared,
    required this.opacity,
    required this.scale,
    required this.effectiveMetrics,
  });

  /// 是否走"按权重位移"的混合路径（当前恒为 `true`）。
  final bool isShared;

  /// 条目整体不透明度（恒为 `1.0`）。
  final double opacity;

  /// 条目整体缩放比例（恒为 `1.0`）。
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
  });

  /// 解析指定 [index] 在当前帧的过渡状态。
  ///
  /// 过渡期一律按"共用条目"处理：位置由 [geometryLayers] 的加权混合给出（见
  /// `_SliverAnimatedZoomGridLayout.getGeometryForChildIndex`），条目本身不做
  /// 原地淡入淡出或缩放。
  ///
  /// 早期实现在这里按"条目只在起始/目标某一层可见"分了一支，让这类条目锁在
  /// 所属档位的屏幕位置上淡入淡出。但可见性是布尔量，而过渡期滚动位置要平移几千
  /// 像素，条目会反复翻转可见性，每次翻转位置就瞬移一次 —— 表现就是整体
  /// "从下往上弹一下"。改为纯加权后，进出视口与普通滚动一致，不再需要单侧淡出。
  FolderZoomItemTransition resolveItemTransition(int index) {
    return FolderZoomItemTransition(
      isShared: true,
      opacity: 1.0,
      scale: 1.0,
      effectiveMetrics: this,
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

  FolderZoomPinchController? _activePinchController;
  bool _pinchAnchorInitialized = false;
  double _pinchBasePixels = 0.0;
  double _pinchBaseSliverOffset = 0.0;
  double _pinchTargetPixels = 0.0;

  /// 缓存的滚动位置，用于免去每帧重新在渲染树里找 viewport。
  ScrollPosition? _cachedPosition;

  /// 取本次换档要操作的滚动位置。
  ///
  /// [FolderZoomSliverBuilder] 的 context 在 [CustomScrollView] **之上**，
  /// 所以 `Scrollable.maybeOf(context)` 永远拿不到它（祖先链上没有 Scrollable）。
  /// 这里改成：显式传入的 controller > 从渲染树里找到的 viewport offset。
  ScrollPosition? _scrollPosition() {
    final controller = widget.controller;
    if (controller != null) {
      return controller.hasClients ? controller.position : null;
    }
    final cached = _cachedPosition;
    if (cached != null &&
        cached.hasPixels &&
        (cached.context.notificationContext?.mounted ?? false)) {
      return cached;
    }
    final position = _findViewportPosition(context.findRenderObject());
    _cachedPosition = position;
    return position;
  }

  /// 在渲染树里定位本 sliver 所属的 [ScrollPosition]。
  ///
  /// 两种常见用法方向相反，都要覆盖：
  /// - [FolderZoomSliverBuilder] 被放进 `CustomScrollView.slivers` 里（多数页面如此）：
  ///   它的 renderObject 就是一个 sliver，viewport 在**祖先**方向；
  /// - 它包住整个 `CustomScrollView`（README 的写法）：viewport 在**后代**里。
  ///
  /// 以前只朝后代遍历，前一种用法恒返回 `null`，滚动补偿静默失效——表现为
  /// 中段/底部换档时内容原地跳变而不是跟着焦点平移。
  static ScrollPosition? _findViewportPosition(RenderObject? root) {
    if (root == null) return null;

    if (root is RenderSliver) {
      RenderObject? node = root.parent;
      while (node != null) {
        if (node is RenderViewportBase) {
          final offset = node.offset;
          if (offset is ScrollPosition) return offset;
        }
        final parent = node.parent;
        node = parent is RenderObject ? parent : null;
      }
      return null;
    }

    ScrollPosition? result;
    void visit(RenderObject node) {
      if (result != null) return;
      if (node is RenderViewportBase) {
        final offset = node.offset;
        if (offset is ScrollPosition) {
          result = offset;
          return;
        }
      }
      node.visitChildren(visit);
    }

    visit(root);
    return result;
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
    if ((_startScrollPixels - _targetScrollPixels).abs() <= 0.5) return;
    final position = _scrollPosition();
    if (position == null ||
        !position.hasPixels ||
        !_viewportTracker.isActiveInViewport) {
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
    if ((position.pixels - clamped).abs() > 0.5) {
      position.jumpTo(clamped);
    }
  }

  void _onPinchChanged() {
    final pinch = _activePinchController;
    if (!mounted || pinch == null) return;
    if (!pinch.isActive) {
      _pinchAnchorInitialized = false;
      return;
    }
    final position = _scrollPosition();
    if (position == null ||
        !position.hasPixels ||
        !_viewportTracker.isActiveInViewport) {
      return;
    }
    if (!_pinchAnchorInitialized) {
      final isPortrait =
          MediaQuery.maybeOrientationOf(context) == Orientation.portrait;
      // 按双指中点重新取锚，手指下的内容在捏合过程中才不会跟着漂。
      _viewportTracker.refreshAnchor(
        focusFraction:
            _focusFractionAt(pinch.focalGlobal, position) ??
                kFolderZoomFocusCenter,
        isPortrait: isPortrait,
      );
      final toTargets = _calculateTargets(
        pinch.targetZoomScale,
        isPortrait: isPortrait,
      );
      final targetTop = _viewportTracker.solveViewportTopFor(
        _layerOf(toTargets, 1.0),
        isPortrait: isPortrait,
      );
      _pinchBasePixels = position.pixels;
      _pinchBaseSliverOffset = _sliverTopForPixels(position.pixels);
      _pinchTargetPixels = (_pinchBasePixels +
              (targetTop - _pinchBaseSliverOffset))
          .clamp(0.0, position.maxScrollExtent);
      _pinchAnchorInitialized = true;
    }
    final targetPixels = lerpDouble(
      _pinchBasePixels,
      _pinchTargetPixels,
      pinch.progress,
    )!;
    if ((position.pixels - targetPixels).abs() > 0.5) {
      position.jumpTo(targetPixels);
    }
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

    // 过渡期：条目位置 = 各档位下该条目的**屏幕位置**的加权平均。
    //
    // 这里刻意不对"该条目在某一层视口内是否可见"做分支。可见性是布尔量，而过渡期间
    // 滚动位置要在几千像素上平移，条目会反复翻转可见性；每翻转一次，位置就在
    // "混合值"与"某一层的锁定值"之间瞬移一次 —— 屏幕上表现为所有条目一起
    // 从下往上弹一下。改成纯加权之后，位置对 progress 连续，翻转不再产生跳变。
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
