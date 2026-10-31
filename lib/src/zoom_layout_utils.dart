import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

/// 一个网格段连续多少帧没被布局到，才认为它已经从页面里移除。
///
/// 只留 1 帧宽限：段被移除后它的 `precede` / 条目数会污染下游段的位置换算，
/// 拖得越久越容易在换档时被算进去。而"某一帧恰好没布局到"在正常滚动里几乎
/// 不会发生（视口会按顺序布局每一个子 sliver）。
const int kSectionFrameGrace = 2;

/// 焦点锚相对内容两端的位置。
enum _ZoomAnchorEdge { none, top, bottom }

/// 页面里**一个参与缩放的网格段**的状态。
///
/// 一个 [FolderZoomSliverBuilder] 下可以挂多个网格（`SliverAnimatedZoomGridDelegate`
/// 的 `section` 区分），它们共用同一套几何（列数 / 字号只取决于宽度和档位），
/// 但各自的条目数、以及在页面里的起始位置都不同。
///
/// 关键是把每段的坐标记全：`precede` 是本段起始边在**页面坐标**里的位置，
/// `gapBefore` 是它之前那段不参与缩放的内容（页头 / 外层 padding / 中间那行介绍）。
/// 后者由 `precede - Σ(上游各段高度)` 反推，因为上游各段高度随档位变、两者相减
/// 正好剩下固定部分 —— 于是跨档求解时下游网格能被正确地整体挪回来。
class _ZoomSectionState {
  _ZoomSectionState(this.id);

  final Object? id;

  double usableWidth = 0.0;
  double outerWidth = 0.0;

  /// 视口顶端在**本段局部坐标**里的位置（`pixels - precede`，起始边在视口下方时为负）。
  double viewportTop = 0.0;
  double remainingPaintExtent = 0.0;

  double listMainAxisSpacing = kFolderListRowSpacing;
  double gridCrossAxisSpacing = kGridCrossAxisSpacing;
  double gridMainAxisSpacing = kGridMainAxisSpacing;

  /// 本段条目总数（由 `computeMaxScrollOffset` 回填）。
  int? contentCount;

  /// 本段起始边在页面坐标里的位置（每次布局刷新）。
  double precede = 0.0;

  /// 本段之前**不参与缩放**的内容高度（页头、外层 padding、中间那行介绍）。
  double gapBefore = 0.0;

  /// [gapBefore] 是否已经量出来过。
  ///
  /// 首帧各段的条目数还没回填，反推不出上游高度；此时所有跨段换算都退回
  /// "本段局部坐标"，也就是不补偿 —— 与"还没有任何几何变化"的真实状态一致。
  bool gapReady = false;

  /// 锚点落在本段时才有意义。
  int anchorIndex = 0;
  double anchorRatio = 0.0;
  double anchorFocusY = 0.0;
  bool hasAnchor = false;

  bool hasMeasurement = false;

  /// 最近一次被布局到的帧序号；用来淘汰已经从页面里移除的段。
  int frameIndex = 0;
}

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
///
/// ## 多段（一页多个网格）
///
/// 上面那套算出来的 `targetTop` 是**本段局部坐标**。页面里还有别的网格时，下游网格
/// 的起始边会随着上游网格一起上下移动，滚动补偿必须把这段位移算进去。所以这里统一
/// 换成**页面坐标**（与 `ScrollPosition.pixels` 同一套）求解：
///
/// ```text
/// pageStart(k, L) = gapBefore_k + Σ_{j<k} H_j(L)     // 第 k 段起始边在页面里的位置
/// targetPixels(L) = pageStart(anchor, L) + targetTop(L)          // 焦点锚定
///                 = pageEnd(L) + tail - viewportHeight           // 贴底
///                 = pixels                                        // 贴顶
/// viewportTop(k, L) = targetPixels(L) - pageStart(k, L)          // 给布局用的局部值
/// ```
///
/// 只有一段时 `pageStart = gapBefore`（常量），公式退化成原来的
/// `目标像素 = 常量 + targetTop`，行为完全不变。
class FolderZoomViewportTracker {
  /// 各段状态；单列表用法下只有键 `null` 一项。
  final Map<Object?, _ZoomSectionState> _sections =
      <Object?, _ZoomSectionState>{};

  /// 按页面位置排好序的段（首个在最上面）。
  List<_ZoomSectionState> _ordered = const <_ZoomSectionState>[];

  /// 读取当前滚动像素值的回调，由 [FolderZoomSliverBuilder] 注入。
  ///
  /// 布局回调里拿不到 [ScrollPosition]，但换档时要把"本地坐标"换算成"滚动像素"，
  /// 需要知道两者之间的固定差值（外层 padding / 前置 sliver 的高度）。这里记下每次
  /// 布局时刻的像素值，换档时就能把"当前像素"还原成同一时刻的段起始边。
  double Function()? scrollPixelsReader;

  /// 读取当前滚动位置上界的回调（`ScrollPosition.maxScrollExtent`）。
  ///
  /// 用来算 [tailExtent]：真实可滚范围里，最后一段内容末端之后还有多长
  /// （外层 `SliverPadding` 的尾部 padding、后面的其它 sliver）。
  double? Function()? scrollMaxPixelsReader;

  /// 当前是否竖屏；几何换算要用（各段一致，所以放在这里）。
  bool isPortrait = false;

  /// 帧序号与最近一次记录时的帧时间戳。
  ///
  /// 用系统帧标识（而不是"某个段出现两次"这类相对信号）来判"这一帧是否已经
  /// 看过这个段"：同一个 sliver 在一帧里可能被布局多次（父级重建、双重 layout），
  /// 而某个段也可能一帧只走一次，两者叠在一起会把"还在"的段误判成已移除。
  /// 一旦误判，`gapBefore` 会被重算成 `precede` 本身（上游高度整段丢失），
  /// 换档时下游列表被顶走上游那一段的高度，反复换档就会一路漂到页面底部。
  int _frameIndex = 0;
  int _lastFrameStamp = -1;

  double _height = 0.0;
  double? _pixelsAtLayout;

  /// 锚点所在段。
  Object? _anchorSectionId;

  /// 锚是否贴在了内容的两端。贴边时直接按"顶 / 底对齐"换算，保证精确。
  _ZoomAnchorEdge _anchorEdge = _ZoomAnchorEdge.none;

  /// 锚定成立那一刻的滚动像素值（贴顶时它就是目标值）。
  double anchorSourcePixels = 0.0;

  /// 最近一次稳态布局所在的档位层。
  FolderZoomGeometryLayer? steadyLayer;

  /// 本 sliver 的内容末端之后、仍然能继续滚动的那段长度（页面坐标）。
  double tailExtent = 0.0;

  /// 锚定假想的视口与真实视口的残差（页面坐标）。
  ///
  /// 只有当滚动被 `maxScrollExtent` 夹住（长度变短、撞到底）时才会非零；
  /// 把它加回每一段的视口顶部，可见性判断才不会和屏幕上看到的内容打架。
  double correction = 0.0;

  bool hasAnchor = false;
  bool hasMeasurement = false;

  /// 过渡期是否处于"多几何层混合"状态；用于只在过渡结束那一帧打一次日志。
  bool _wasMixing = false;

  /// 上一次布局时 `pixels - scrollOffset` 的值；恒定才算对齐，变化就说明挑错了位置。
  double? _lastPrecede;

  // ---------------------------------------------------------------------------
  // 兼容单段用法的读取接口（默认取锚所在段，没有锚时取第一段）
  // ---------------------------------------------------------------------------

  _ZoomSectionState? get _defaultSection {
    final anchored = _sections[_anchorSectionId];
    if (anchored != null) return anchored;
    if (_ordered.isNotEmpty) return _ordered.first;
    return _sections[null];
  }

  /// 视口高度（各段相同）。
  double get viewportHeight => math.max(0.0, _height);

  double get usableWidth => _defaultSection?.usableWidth ?? 0.0;
  double get outerWidth => _defaultSection?.outerWidth ?? 0.0;
  double get viewportTop => _defaultSection?.viewportTop ?? 0.0;
  double get viewportBottom => viewportTop + viewportHeight;
  double get remainingPaintExtent =>
      _defaultSection?.remainingPaintExtent ?? 0.0;
  double get precede => _defaultSection?.precede ?? 0.0;
  int? get contentCount => _defaultSection?.contentCount;

  set contentCount(int? value) {
    if (value == null) return;
    _section(null).contentCount = value;
  }

  /// 回填某一段的条目总数（由该段网格的 `computeMaxScrollOffset` 调用）。
  void setContentCount(Object? section, int count) {
    _section(section).contentCount = count;
  }

  /// 某一段上一次回填的条目总数；还没回填过时返回 `null`。
  ///
  /// 布局侧要用它把「锁在屏幕上的单侧可见条目」夹回本段的内容范围
  /// （见 `_SliverAnimatedZoomGridLayout._clampPinned`）。
  int? contentCountOf(Object? section) => _sections[section]?.contentCount;

  int get anchorIndex => _defaultSection?.anchorIndex ?? 0;
  double get anchorRatio => _defaultSection?.anchorRatio ?? 0.0;
  double get anchorFocusY => _defaultSection?.anchorFocusY ?? 0.0;

  /// 最近一次布局时的滚动像素值。
  double? get pixelsAtLayout => _pixelsAtLayout;

  /// 视口顶端在局部坐标里的最小值（= 页面 `pixels == 0` 时的取值）。
  double get minViewportTop => -precede;

  /// 页面是否已经滚到最顶端。
  bool get atScrollStart {
    final double? px = _pixelsAtLayout;
    if (px != null) return px <= 0.5;
    return viewportTop <= 0.5;
  }

  /// 是否有任意一段在视口里可见（用于多段时仅激活可见段的滚动吸附）。
  bool get isActiveInViewport {
    for (final s in _ordered) {
      if (s.hasMeasurement && s.remainingPaintExtent > 10.0) return true;
    }
    return false;
  }

  /// 参与布局的段 id（单列表时是 `[null]`）。
  List<Object?> get sectionIds => _sections.keys.toList(growable: false);

  /// 调试用：当前锚定方式的名称（`top` / `bottom` / `none`）。
  String get anchorEdgeName => _anchorEdge.name;

  // ---------------------------------------------------------------------------
  // 段管理
  // ---------------------------------------------------------------------------

  _ZoomSectionState _section(Object? id) =>
      _sections.putIfAbsent(id, () => _ZoomSectionState(id));

  _ZoomSectionState _sectionOf(Object? id) =>
      _sections[id] ?? _ZoomSectionState(id);

  /// 进入/保持在当前帧，并淘汰已经连续若干帧没被布局到的段。
  ///
  /// 帧标识取 `SchedulerBinding.currentFrameTimeStamp`：同一帧内所有布局回调看到
  /// 的值相同，跨帧递增，而且与 build 次数无关 —— 这正是"这一帧有没有看过某个段"
  /// 需要的信息。宽限 [kSectionFrameGrace] 帧：某一段偶尔一帧没被布局（缓存范围外）
  /// 不该让它连同条目数一起被丢掉，否则上游补偿会静默失效。
  void _beginFrame() {
    final int stamp =
        SchedulerBinding.instance.currentFrameTimeStamp.inMicroseconds;
    if (stamp == _lastFrameStamp) return;
    _lastFrameStamp = stamp;
    _frameIndex++;
    final int keepFrom = _frameIndex - kSectionFrameGrace;
    if (keepFrom <= 0) return;
    final int before = _sections.length;
    _sections.removeWhere((key, value) => value.frameIndex < keepFrom);
    if (_sections.length == before) return;
    _reorder();
    if (_anchorSectionId != null && !_sections.containsKey(_anchorSectionId)) {
      _anchorSectionId = null;
      hasAnchor = false;
    }
  }

  void _reorder() {
    final list = <_ZoomSectionState>[
      for (final s in _sections.values)
        if (s.hasMeasurement) s,
    ]..sort((a, b) => a.precede.compareTo(b.precede));
    _ordered = list;
  }

  // ---------------------------------------------------------------------------
  // 几何换算（全部按段取参数）
  // ---------------------------------------------------------------------------

  SliverGridGeometry _geomIn(
    _ZoomSectionState s,
    FolderZoomGeometryLayer layer,
    int index,
  ) {
    return _SliverAnimatedZoomGridLayout.geometryInLayer(
      layer: layer,
      index: index,
      usableWidth: s.usableWidth,
      outerWidth: s.outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: s.listMainAxisSpacing,
      gridCrossAxisSpacing: s.gridCrossAxisSpacing,
      gridMainAxisSpacing: s.gridMainAxisSpacing,
    );
  }

  double _strideIn(_ZoomSectionState s, FolderZoomGeometryLayer layer) {
    return _SliverAnimatedZoomGridLayout.mainStrideFor(
      layer: layer,
      usableWidth: s.usableWidth,
      outerWidth: s.outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: s.listMainAxisSpacing,
      gridCrossAxisSpacing: s.gridCrossAxisSpacing,
      gridMainAxisSpacing: s.gridMainAxisSpacing,
    );
  }

  /// 本段在 [layer] 档位下的内容高度。
  double _extentIn(_ZoomSectionState s, FolderZoomGeometryLayer layer) {
    final int count = s.contentCount ?? 0;
    if (count <= 0) return 0.0;
    return _SliverAnimatedZoomGridLayout.contentExtentIn(
      layer: layer,
      childCount: count,
      usableWidth: s.usableWidth,
      outerWidth: s.outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: s.listMainAxisSpacing,
      gridCrossAxisSpacing: s.gridCrossAxisSpacing,
      gridMainAxisSpacing: s.gridMainAxisSpacing,
    );
  }

  /// 本段在**混合几何**（过渡期）下的内容高度。
  double _mixedExtent(
    _ZoomSectionState s,
    List<FolderZoomGeometryLayer> layers,
  ) {
    if (layers.isEmpty) return 0.0;
    double sum = 0.0;
    double weight = 0.0;
    for (final layer in layers) {
      sum += _extentIn(s, layer) * layer.weight;
      weight += layer.weight;
    }
    if (weight <= 1e-6) return 0.0;
    return sum / weight;
  }

  /// 本段起始边在页面坐标里的位置（按 [layer] 档位）。
  double _pageStartIn(_ZoomSectionState s, FolderZoomGeometryLayer layer) {
    double start = s.gapBefore;
    for (final other in _ordered) {
      if (identical(other, s)) break;
      start += _extentIn(other, layer);
    }
    return start;
  }

  double _pageStartMixed(
    _ZoomSectionState s,
    List<FolderZoomGeometryLayer> layers,
  ) {
    double start = s.gapBefore;
    for (final other in _ordered) {
      if (identical(other, s)) break;
      start += _mixedExtent(other, layers);
    }
    return start;
  }

  /// 整页可缩放内容的末端（页面坐标）。
  double _pageEndIn(FolderZoomGeometryLayer layer) {
    if (_ordered.isEmpty) return 0.0;
    final last = _ordered.last;
    return _pageStartIn(last, layer) + _extentIn(last, layer);
  }

  double _pageEndMixed(List<FolderZoomGeometryLayer> layers) {
    if (_ordered.isEmpty) return 0.0;
    final last = _ordered.last;
    return _pageStartMixed(last, layers) + _mixedExtent(last, layers);
  }

  /// [layer] 档位下页面允许滚到的最大值（贴底时视口顶端的页面坐标）。
  double maxPagePixelsFor(FolderZoomGeometryLayer layer) =>
      _pageEndIn(layer) + tailExtent - viewportHeight;

  /// [layer] 档位下本段视口顶端允许的最大值（局部坐标）。
  double? maxViewportTopFor(
    FolderZoomGeometryLayer layer, {
    Object? section,
    bool isPortrait = false,
  }) {
    if (_ordered.isEmpty) return null;
    final s = _sectionOf(section);
    if (s.contentCount == null) return null;
    return maxPagePixelsFor(layer) - _pageStartIn(s, layer);
  }

  /// [layer] 档位在条目总数固定时的最大滚动偏移（页面坐标）。
  double? maxScrollOffsetFor(
    FolderZoomGeometryLayer layer, {
    bool isPortrait = false,
  }) {
    if (_ordered.isEmpty) return null;
    if (_ordered.every((s) => (s.contentCount ?? 0) <= 0)) return null;
    return math.max(0.0, maxPagePixelsFor(layer));
  }

  // ---------------------------------------------------------------------------
  // 布局回填
  // ---------------------------------------------------------------------------

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
    Object? section,
  }) {
    // 先推进帧号、淘汰旧段，再取本段：新建的段 `frameIndex` 还是 0，若在淘汰之后
    // 才创建就不会被自己这一轮的清理顺手删掉（删掉的代价是条目数一起丢掉）。
    _beginFrame();
    final s = _section(section);
    s.frameIndex = _frameIndex;
    s.usableWidth = usableWidth;
    s.outerWidth = outerWidth;
    s.viewportTop = viewportTop;
    s.remainingPaintExtent = remainingPaintExtent;
    s.listMainAxisSpacing = listMainAxisSpacing;
    s.gridCrossAxisSpacing = gridCrossAxisSpacing;
    s.gridMainAxisSpacing = gridMainAxisSpacing;
    s.hasMeasurement = true;
    hasMeasurement = true;

    this.isPortrait = isPortrait;
    _height = math.max(0.0, viewportBottom - viewportTop);

    final double? px = scrollPixelsReader?.call();
    if (px != null) {
      _pixelsAtLayout = px;
      s.precede = math.max(0.0, px - viewportTop);
    }

    _reorder();
    _refreshGapBefore(layers);

    final double? layoutPixels = _pixelsAtLayout;
    if (layoutPixels != null && _sections.length == 1) {
      final double? last = _lastPrecede;
      if (last == null || (s.precede - last).abs() > 1.0) {
        zoomLog('align', () {
          return 'top=${zd(viewportTop)} px=${zd(layoutPixels)} '
              'precede=${zd(s.precede)} '
              'delta=${last == null ? '-' : zd(s.precede - last)} '
              'layers=${layers.length}';
        });
        _lastPrecede = s.precede;
      }
    }

    if (!isAnimating && layers.length == 1) {
      steadyLayer = layers.first;
      _recomputeAnchor(focusFraction, isPortrait);
      _refreshTailExtent(layers);
      correction = 0.0;
      if (_wasMixing) {
        _wasMixing = false;
        zoomLog('layout', () {
          return 'settle top=${zd(viewportTop)} px=${zd(layoutPixels)} '
              'anchor=${_anchorEdge.name}#$anchorIndex r=${zd(anchorRatio, 3)} '
              'f=${zd(anchorFocusY)} layer=${_layerTag(layers.first)} '
              'tail=${zd(tailExtent)} '
              'sections=${_ordered.length} '
              'pageMax=${zd(maxPagePixelsFor(layers.first))}';
        });
      }
      return;
    }
    _wasMixing = true;

    if (!hasAnchor || layers.isEmpty) return;

    // 过渡期保留锚，只把"假想视口"与真实视口的残差算出来（页面坐标）。
    double assumed = 0.0;
    double weight = 0.0;
    for (final layer in layers) {
      final double? target = targetPixelsForLayer(layer);
      if (target == null) continue;
      assumed += target * layer.weight;
      weight += layer.weight;
    }
    if (weight > 1e-6 && layoutPixels != null) {
      correction = layoutPixels - assumed / weight;
    }
    zoomLog('layout', () {
      return 'mix top=${zd(viewportTop)} px=${zd(layoutPixels)} '
          'assumed=${weight > 1e-6 ? zd(assumed / weight) : 'n/a'} '
          'corr=${zd(correction)} anchor=${_anchorEdge.name}#$anchorIndex '
          'r=${zd(anchorRatio, 3)} f=${zd(anchorFocusY)} '
          'vh=${zd(viewportHeight)} '
          'maxMix=${zd(maxPagePixelsFor(layers.last))} '
          'sections=${_ordered.length} '
          'layers=${layers.map(_layerTag).join(',')}';
    });
  }

  /// 用上游各段的当前高度反推本段之前的固定内容高度。
  ///
  /// 只在**稳态**（单层几何）下刷新：过渡期各段高度是插值出来的，`precede` 减掉
  /// 的却是混合高度，算出来的差值既不是这一档也不是那一档的值。它本来是个与档位
  /// 无关的常量，用插值反推只会把它带偏，而下游每一次 `pageStart` 都依赖它。
  void _refreshGapBefore(List<FolderZoomGeometryLayer> layers) {
    if (layers.length != 1) return;
    for (final s in _ordered) {
      if (!s.hasMeasurement) continue;
      double upstream = 0.0;
      bool ready = true;
      for (final other in _ordered) {
        if (identical(other, s)) break;
        if (other.contentCount == null) ready = false;
        upstream += _mixedExtent(other, layers);
      }
      if (!ready) continue;
      s.gapBefore = s.precede - upstream;
      s.gapReady = true;
    }
  }

  /// 稳态下刷新 [tailExtent]：真实可滚上界与最后一段内容末端之间还差多少。
  ///
  /// 只在单层稳态调用 —— 那时 `precede` 与各段高度都是确定的，而过渡期的内容总高
  /// 每帧在变，算出来的 tail 只会是中间值。
  void _refreshTailExtent(List<FolderZoomGeometryLayer> layers) {
    final double? maxPixels = scrollMaxPixelsReader?.call();
    if (maxPixels == null || _ordered.isEmpty) return;
    if (_pixelsAtLayout == null) return;
    if (viewportHeight <= 1.0) return;
    final double end = _pageEndMixed(layers);
    final double tail = maxPixels + viewportHeight - end;
    // 只信任正向余量：读到过期上界（上一帧的内容长度）时会算出负数，保留旧值。
    if (tail >= -0.5) tailExtent = math.max(0.0, tail);
  }

  // ---------------------------------------------------------------------------
  // 锚点
  // ---------------------------------------------------------------------------

  /// 用新的焦点高度重新计算锚点（捏合开始时按手指位置重新取锚）。
  void refreshAnchor({
    double focusFraction = kFolderZoomFocusCenter,
    bool isPortrait = false,
  }) {
    if (steadyLayer == null || !hasMeasurement) return;
    this.isPortrait = isPortrait;
    _recomputeAnchor(focusFraction, isPortrait);
  }

  void _setAnchorSection(_ZoomAnchorEdge edge, _ZoomSectionState? s) {
    _anchorEdge = edge;
    _anchorSectionId = s?.id;
    for (final other in _sections.values) {
      other.hasAnchor = identical(other, s);
    }
  }

  void _recomputeAnchor(double focusFraction, bool isPortrait) {
    final layer = steadyLayer;
    final height = viewportHeight;
    if (layer == null || _ordered.isEmpty || height <= 1.0) return;
    if (!hasMeasurement) return;

    final double px = _pixelsAtLayout ?? 0.0;
    hasAnchor = true;
    anchorSourcePixels = px;

    // 贴住两端时直接记成"顶 / 底对齐"，换算精确到像素，且不会因为
    // 焦点落在最后一条的槽位里而少滚一行。
    //
    // 顶端的判据是"页面已经滚到最顶端"（再没有向上滚的余量），而不是
    // `viewportTop <= 0.5`：列表上方还有 header / padding 时，起始边贴在视口顶端
    // **之下**也会让 `viewportTop` 等于 0 或负数，那种情况恰恰要正常按焦点补偿滚动。
    if (px <= 0.5) {
      final first = _ordered.first;
      _setAnchorSection(_ZoomAnchorEdge.top, first);
      first
        ..anchorIndex = 0
        ..anchorRatio = 0.0
        ..anchorFocusY = 0.0;
      return;
    }

    // 底端判据：**最后一段的内容末端已经进了视口**。
    //
    // 内容比视口矮时 `pageMax` 是负数，"滚到它之上"同样成立，判据不需要额外的
    // 下限门槛。条目总数还没回填（首帧）时算不出内容总高，退回不判底。
    final last = _ordered.last;
    if ((last.contentCount ?? 0) > 0) {
      final double lastLocalMax =
          maxPagePixelsFor(layer) - _pageStartIn(last, layer);
      // 同样从 `precede` 现场换算，不用 `last.viewportTop`（可能是上一帧留下的值）。
      if (px - last.precede >= lastLocalMax - 0.5) {
        _setAnchorSection(_ZoomAnchorEdge.bottom, last);
        last
          ..anchorIndex = 0
          ..anchorRatio = 1.0
          ..anchorFocusY = height;
        return;
      }
    }

    // 焦点锚：先按"视口中心"找焦点落在哪一段，再用该段的局部坐标取锚条目。
    final double preferred =
        focusFraction.clamp(0.0, 1.0) * height;
    final double probe = px + preferred;
    _ZoomSectionState anchor = last;
    for (final s in _ordered) {
      final double start = _pageStartIn(s, layer);
      if (probe < start + _extentIn(s, layer) - kFolderZoomVisibilityEpsilon) {
        anchor = s;
        break;
      }
    }

    _setAnchorSection(_ZoomAnchorEdge.none, anchor);

    // 本段视口顶端在段局部坐标里的位置。**不用** `anchor.viewportTop`：那是上一次
    // 布局回填的值，而一帧里各段的布局先后不定（上游段先记录时，下游段的
    // `viewportTop` 还是上一帧的），过渡刚结束那一帧它会带着混合几何的残值，
    // 锚条目会因此错开一行。`precede` 是页面坐标、稳态下恒定，减去当前像素
    // 就是同一时刻的局部值。
    final double sectionTop = px - anchor.precede;
    double focus = _resolveFocusY(
      height,
      focusFraction,
      layer: layer,
      pageTop: px,
      sectionTop: sectionTop,
    );
    // 本段起始边还在视口顶端之下（上方有 header、页面刚打开）时，焦点**上方没有
    // 内容**：把焦点压到第一条上，解出来的目标就等于"把起始边钉在原地"，
    // 不会把页面莫名往下滚一屏。
    focus = math.max(focus, -sectionTop);
    final double contentPoint = sectionTop + focus;

    int index = _minIndexFor(anchor, layer, contentPoint);
    final double stride = _strideIn(anchor, layer);
    var geom = _geomIn(anchor, layer, index);

    // 粘住上一次的锚条目。
    //
    // 同一**行**里的条目几何完全一样（`scrollOffset` 相同），用哪一个都能锚定，
    // 但跨档时它们会落到不同的行：6 列下索引 40 在第 6 行，8 列下却在第 5 行。
    // 若每次稳点都按"该行的第一个条目"重新取锚（40 -> 36），往回换档时锚就变成
    // 了另一个条目，一来一回净丢一行 —— 反复换档就会缓慢地一路漂走。
    // 只要上一次的锚条目还和焦点落在同一行，就继续用它，来回换档才能回到原位。
    final int? sticky = anchor.hasAnchor ? anchor.anchorIndex : null;
    if (sticky != null &&
        sticky != index &&
        sticky >= 0 &&
        sticky < (anchor.contentCount ?? 0) &&
        (_geomIn(anchor, layer, sticky).scrollOffset - geom.scrollOffset).abs() <
            0.5) {
      index = sticky;
      geom = _geomIn(anchor, layer, index);
    }

    anchor
      ..anchorIndex = index
      ..anchorRatio = stride <= 0.5
          ? 0.0
          : ((contentPoint - geom.scrollOffset) / stride).clamp(0.0, 1.0)
      ..anchorFocusY = focus;
  }

  /// 按"距顶 / 距底不足一屏"把焦点渐变到 `0` / `1`，让两端退化为顶 / 底对齐。
  double _resolveFocusY(
    double height,
    double focusFraction, {
    required FolderZoomGeometryLayer layer,
    required double pageTop,
    required double sectionTop,
  }) {
    final double preferred = focusFraction.clamp(0.0, 1.0) * height;

    // 距顶不足一屏时把焦点渐变到 `0`，让顶端退化成"顶对齐"、不撞滚动边界。
    //
    // 判据分两层：
    // - `sectionTop < 0`（本段起始边还在视口顶端**之下**，页头 / 前面还有内容）：
    //   不渐变。此时焦点上方是本段之前的内容，"压到本段第一条"等于跳过补偿，
    //   用户看到的焦点内容会被整体甩走；交给 `_recomputeAnchor` 里的
    //   `focus = max(focus, -sectionTop)` 兜底。
    // - 否则按"页面已经滚过多少**可缩放内容**"渐变（扣掉第一个网格段之前的页头）：
    //   不能直接用段局部的偏移 —— 一页多段时第二段在中段时它的局部偏移可能
    //   只有一两百（离"本段开头"很近），但页面其实滚出去好几千，按局部值渐变会
    //   把焦点从视口中心一路压到本段顶部，也就是"焦点位置不对"。
    final double leading =
        pageTop - (_ordered.isEmpty ? 0.0 : _ordered.first.precede);
    final double topBlend = sectionTop < 0.0
        ? 0.0
        : (1.0 - math.max(0.0, leading) / height).clamp(0.0, 1.0);
    double focus = lerpDouble(preferred, 0.0, topBlend)!;

    // 底部渐变同理按**页面**还能不能滚来判：本段自己可能还能滚很久，但页面已经
    // 到底了，此时任何档位都只能贴底，焦点必须退化成"底对齐"。
    final double pageMax = maxPagePixelsFor(layer);
    if (pageMax > 1.0) {
      final double bottomBlend =
          (1.0 - (pageMax - pageTop) / height).clamp(0.0, 1.0);
      focus = lerpDouble(focus, height, bottomBlend)!;
    }
    return focus.clamp(0.0, height);
  }

  // ---------------------------------------------------------------------------
  // 求解：目标滚动像素
  // ---------------------------------------------------------------------------

  /// [layer] 档位下，焦点锚对应的**滚动像素**（页面坐标）。
  ///
  /// 过渡动画直接把它当作目标滚动位置；单段时它等于"本段局部 targetTop"，
  /// 多段时已经包含了上游各段高度变化带来的整体平移。
  double? targetPixelsForLayer(FolderZoomGeometryLayer layer) {
    if (!hasMeasurement || !hasAnchor) return null;
    if (!(_sections[_anchorSectionId]?.gapReady ?? false)) return null;
    switch (_anchorEdge) {
      case _ZoomAnchorEdge.top:
        return anchorSourcePixels;
      case _ZoomAnchorEdge.bottom:
        return maxPagePixelsFor(layer);
      case _ZoomAnchorEdge.none:
        break;
    }
    final s = _sections[_anchorSectionId];
    if (s == null || !s.hasAnchor) return null;
    final geom = _geomIn(s, layer, s.anchorIndex);
    final double top =
        geom.scrollOffset + s.anchorRatio * _strideIn(s, layer) - s.anchorFocusY;
    return _pageStartIn(s, layer) + top;
  }

  /// [layer] 档位下，某一段视口顶端的**局部**偏移（含过渡期残差修正，已夹取）。
  double viewportTopForLayer(
    FolderZoomGeometryLayer layer, {
    Object? section,
    bool isPortrait = false,
  }) {
    final s = _sectionOf(section);
    if (!hasMeasurement || !hasAnchor || !s.gapReady) return s.viewportTop;
    final double? page = targetPixelsForLayer(layer);
    if (page == null) return s.viewportTop;
    double top = page + correction - _pageStartIn(s, layer);
    // 底部贴边时 `targetPixelsForLayer` 已经精确给出贴底位置，不要再夹取。
    if (_anchorEdge != _ZoomAnchorEdge.bottom) {
      final double maxTop = maxPagePixelsFor(layer) - _pageStartIn(s, layer);
      final double clamped = math.min(top, maxTop);
      if ((clamped - top).abs() > 0.5) {
        zoomLog('probe', () {
          return 'layerTop clamped ${zd(top)} -> ${zd(clamped)} '
              'maxTop=${zd(maxTop)} tail=${zd(tailExtent)} '
              'layer=${_layerTag(layer)}';
        });
      }
      top = clamped;
    }
    // 下界是"页面滚到 0"对应的坐标，不是 0：上方还有 header / padding 时它是负的。
    return math.max(-s.precede, top);
  }

  /// 兼容旧名字：返回同一个页面坐标目标。
  double solveViewportTopFor(
    FolderZoomGeometryLayer layer, {
    bool isPortrait = false,
  }) {
    return targetPixelsForLayer(layer) ?? viewportTop;
  }

  // ---------------------------------------------------------------------------
  // 单侧可见条目的冻结表（按段各一份）
  // ---------------------------------------------------------------------------

  /// 过渡开始时**一次性**冻结"哪些条目原地淡入淡出、锁在哪个屏幕位置"。
  ///
  /// [mixLayers] 是此刻屏幕上**实际生效**的几何层（过渡中再次换档时，它就是上一段
  /// 过渡的混合结果，而不是某个纯净档位），[targetLayer] / [targetViewportTop]
  /// 是本次过渡的终点。这样"锁在原位"的参照系始终是**上一帧真实画出来的位置**，
  /// 连点两档也不会让被锁定的条目瞬移 —— 已经锁定的条目由 [previous] 带过来。
  ///
  /// 判定必须一次算完并冻结（原因见 [FolderZoomItemPinning] 的文档），并且**按段
  /// 各算一份**：每段的条目索引都从 0 开始，混着用会让两段的条目互相顶替。
  FolderZoomItemPinning? buildPinning({
    required List<FolderZoomGeometryLayer> mixLayers,
    required FolderZoomGeometryLayer targetLayer,
    required double targetViewportTop,
    required bool isPortrait,
    Object? section,
    FolderZoomItemPinning? previous,
    double previousProgress = 0.0,
  }) {
    final s = _sectionOf(section);
    final int count = s.contentCount ?? 0;
    final double height = viewportHeight;
    if (count <= 0 || !hasMeasurement) return null;
    if (mixLayers.isEmpty || height <= 1.0) return null;

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
        viewportTopForLayer(layer, section: section, isPortrait: isPortrait),
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
        _minIndexFor(s, layer, mixTops[i] - height) - layer.crossAxisCount,
      );
      hi = math.max(
        hi,
        _maxIndexFor(s, layer, mixTops[i] + height * 2) + layer.crossAxisCount,
      );
    }
    lo = math.min(
      lo,
      _minIndexFor(s, targetLayer, targetViewportTop - height) -
          targetLayer.crossAxisCount,
    );
    hi = math.max(
      hi,
      _maxIndexFor(s, targetLayer, targetViewportTop + height * 2) +
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
          final geometry = _geomIn(s, layer, index);
          weight += layer.weight;
          top += (geometry.scrollOffset - mixTops[i]) * layer.weight;
          extent += geometry.mainAxisExtent * layer.weight;
        }
        if (weight <= 1e-6) continue;
        top /= weight;
        extent /= weight;

        final targetGeometry = _geomIn(s, targetLayer, index);
        final double targetTop = targetGeometry.scrollOffset - targetViewportTop;

        final bool visibleFrom = _isOnScreen(top, extent, height);
        final bool visibleTo =
            _isOnScreen(targetTop, targetGeometry.mainAxisExtent, height);

        kind = visibleFrom == visibleTo
            ? FolderZoomItemPin.shared
            : (visibleFrom
                ? FolderZoomItemPin.fadeOut
                : FolderZoomItemPin.fadeIn);
        lockedLayer =
            kind == FolderZoomItemPin.fadeOut ? dominant : targetLayer;
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
    _ZoomSectionState s,
    FolderZoomGeometryLayer layer,
    double scrollOffset,
  ) {
    return _SliverAnimatedZoomGridLayout.minChildIndexIn(
      layer: layer,
      scrollOffset: scrollOffset,
      usableWidth: s.usableWidth,
      outerWidth: s.outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: s.listMainAxisSpacing,
      gridCrossAxisSpacing: s.gridCrossAxisSpacing,
      gridMainAxisSpacing: s.gridMainAxisSpacing,
    );
  }

  int _maxIndexFor(
    _ZoomSectionState s,
    FolderZoomGeometryLayer layer,
    double targetEndScrollOffset,
  ) {
    return _SliverAnimatedZoomGridLayout.maxChildIndexIn(
      layer: layer,
      targetEndScrollOffset: targetEndScrollOffset,
      usableWidth: s.usableWidth,
      outerWidth: s.outerWidth,
      isPortrait: isPortrait,
      listMainAxisSpacing: s.listMainAxisSpacing,
      gridCrossAxisSpacing: s.gridCrossAxisSpacing,
      gridMainAxisSpacing: s.gridMainAxisSpacing,
    );
  }

  /// 几何层的简短标记，例如 `lx1/w1.00/e74.0`、`gx4/w0.00/th0.0`。
  static String _layerTag(FolderZoomGeometryLayer layer) {
    final head = '${layer.isGrid ? 'g' : 'l'}x${layer.crossAxisCount}'
        '/w${layer.weight.toStringAsFixed(2)}';
    return layer.isGrid
        ? '$head/th${layer.gridTextHeight.toStringAsFixed(1)}'
        : '$head/e${layer.listExtent.toStringAsFixed(1)}';
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

  /// 本次过渡开始时冻结的"单侧可见条目"处置表（默认段，即 `section == null`）。
  ///
  /// 为 `null` 时表示没有任何条目需要原地淡入淡出，全部按加权位移处理。
  final FolderZoomItemPinning? itemPinning;

  /// 一页多个网格时，每个段各自的冻结表（键是 `SliverAnimatedZoomGridDelegate.section`）。
  ///
  /// 每段的条目索引都从 0 开始，共用一张表会让两段的条目互相顶替，所以必须按段分开。
  final Map<Object?, FolderZoomItemPinning> sectionPinning;

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
    this.sectionPinning = const <Object?, FolderZoomItemPinning>{},
    this.transitionProgress = 0.0,
  });

  /// 取某个段的冻结表；没注册过的段不会借用别人的分类结果。
  FolderZoomItemPinning? pinningFor(Object? section) {
    if (section == null) return itemPinning;
    return sectionPinning[section];
  }

  /// 解析指定 [index] 在当前帧的过渡状态。
  ///
  /// 分两路：
  /// - 起始 / 目标档位**都可见**的条目（绝大多数）走加权位移，位置由
  ///   [geometryLayers] 的混合给出（见 `_SliverAnimatedZoomGridLayout
  ///   .getGeometryForChildIndex`），不透明、不缩放。
  /// - 只有一侧可见的条目位置被 [pinningFor] 给出的冻结表锁死在该档位的屏幕位置上
  ///   （布局侧不再移动它），这里只负责给出淡入 / 淡出的不透明度与缩放。
  ///
  /// [section] 必须与创建该条目时 `SliverAnimatedZoomGridDelegate.section` 一致；
  /// 单列表用法留空即可。
  ///
  /// 分类结果在过渡开始时冻结，逐帧不会翻转 —— 这是"原地淡入淡出"能站住的前提，
  /// 细节见 [FolderZoomItemPinning]。
  FolderZoomItemTransition resolveItemTransition(int index, {Object? section}) {
    final FolderZoomItemPinning? pinning = pinningFor(section);
    final FolderZoomItemPin pin =
        pinning?.pinOf(index) ?? FolderZoomItemPin.shared;
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
        pinning?.opacityAt(index, t) ?? (pin == FolderZoomItemPin.fadeOut ? 1.0 - t : t);
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

/// 交接点两侧压暗半窗：越过滞回带之后，还要再走这么远才恢复到全不透明。
const double kFolderZoomContentHandoffFadeHalfWindow = 0.12;

/// 交接带内（`[下界, 上界]`）的内容不透明度。
///
/// 必须是 `0`：网格与列表的**内容排版**是两套完全不同的布局（封面在上 / 封面在左、
/// 标题在封面下方 / 标题垂直居中），交接那一刻只能整份换掉、无法逐属性插值。
/// 只要换的一瞬间还看得见，条目内部的封面与文字就会"跳"一下 —— 实测标题会在
/// 交接帧瞬移 30~40px，而当时的不透明度还有 0.74（`|morph-0.5|` 与滞回阈值
/// 0.45/0.55 不同源，是最初的实现留下的错位）。压到 0 之后，换布局发生在
/// 完全看不见的那几帧里，视觉上只剩"淡出 → 淡入"。
const double kFolderZoomContentHandoffMinOpacity = 0.0;

/// 向 [FolderZoomSliverBuilder] 的整棵子树下发当前帧的 [FolderZoomLayoutMetrics]。
///
/// 一个页面里有多段可缩放列表时，各段**必须**共用同一个 builder：滚动补偿按页面
/// 坐标统一结算，各段自己建 builder 会互相顶走（上游那一段在下游的 tracker 里根本
/// 不存在，换档后下游只按自己的局部坐标补偿，被上游的高度变化顶掉一截；两个
/// builder 还会同时往同一个 [ScrollPosition] 写像素值）。
///
/// 有了这个 scope，段组件不必再手工把 metrics 从页面传下来 —— 见
/// [FolderZoomSectionHost]。
///
/// 注意它只描述**页面级**度量，不参与"单侧可见条目"那种条目级锁定（那是
/// `ZoomItemEffectiveMetrics` 的职责，优先级更高）。
class FolderZoomMetricsScope extends InheritedWidget {
  const FolderZoomMetricsScope({
    super.key,
    required this.metrics,
    required super.child,
  });

  final FolderZoomLayoutMetrics metrics;

  static FolderZoomLayoutMetrics? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<FolderZoomMetricsScope>()
        ?.metrics;
  }

  @override
  bool updateShouldNotify(FolderZoomMetricsScope oldWidget) =>
      !identical(oldWidget.metrics, metrics);
}

/// 一个"缩放段"的容器：祖先有 [FolderZoomMetricsScope] 就直接用页面下发的度量，
/// 否则自建一个 [FolderZoomSliverBuilder]。
///
/// 用途是让同一份列表组件既能作为多段页面里的一段（由页面统一提供 builder），
/// 也能单独成页（组件自己就是宿主）。相比"给列表组件加一个可选 `metrics` 参数"，
/// 这里的判据是**树的位置**而不是调用方有没有记得传值：漏传会在结构上退回
/// 多 builder（补偿互相顶走），而这里不可能漏。
class FolderZoomSectionHost extends StatelessWidget {
  const FolderZoomSectionHost({
    super.key,
    required this.zoomScale,
    required this.width,
    required this.builder,
    this.controller,
  });

  /// 只在没有祖先 scope（即本段自己就是宿主）时用到。
  final double zoomScale;

  /// 只在没有祖先 scope 时用到。
  final double width;

  /// 只在没有祖先 scope 时传给自建的 builder。
  final ScrollController? controller;

  final Widget Function(BuildContext context, FolderZoomLayoutMetrics metrics)
      builder;

  @override
  Widget build(BuildContext context) {
    final hostMetrics = FolderZoomMetricsScope.maybeOf(context);
    if (hostMetrics != null) return builder(context, hostMetrics);
    return FolderZoomSliverBuilder(
      zoomScale: zoomScale,
      width: width,
      controller: controller,
      builder: builder,
    );
  }
}

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

  /// 本次过渡开始时冻结的"单侧可见条目"处置表（按段各一份，单列表时只有键 `null`）。
  ///
  /// 只在 [animate] 换档时生成一次，整段过渡复用（原因见 [FolderZoomItemPinning]）。
  /// 过渡结束 / 转入捏合时清空，避免下一段过渡沿用上一段的位置。
  Map<Object?, FolderZoomItemPinning> _sectionPinning =
      const <Object?, FolderZoomItemPinning>{};

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

  /// 捏合路径的"单侧可见条目"冻结表（按段各一份），与 [_sectionPinning] 同一套机制。
  ///
  /// 捏合的进度由手指驱动、方向还可能中途反转，所以不能像点击换档那样在
  /// `_applyTargets` 里算一次：这里按 `(起始档位, 目标档位)` 缓存，方向确定的那一帧
  /// 冻结一次；目标反转时重算 —— 反转只可能发生在双指间距跨过手势起点
  /// （`progress ≈ 0`）的那一帧，此刻两层几何的权重正好是 `(1, 0)`，重算等价于
  /// 重新按起始档位判定，不会有条目从锁定位置瞬移。
  Map<Object?, FolderZoomItemPinning> _pinchPinning =
      const <Object?, FolderZoomItemPinning>{};
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

  /// 当前滚动位置上界；内容尺寸还没算出来时返回 `null`。
  ///
  /// 只在 tracker 的稳态分支用来推算"内容末端之后还能滚多长"，
  /// 所以宁可不给，也不要拿一个过期的 0 当上界。
  double? _currentScrollMaxPixels() {
    final position = _scrollPosition();
    if (position == null || !position.hasPixels) return null;
    if (!position.hasContentDimensions) return null;
    return position.maxScrollExtent;
  }

  @override
  void initState() {
    super.initState();
    _viewportTracker.scrollPixelsReader = _currentScrollPixels;
    _viewportTracker.scrollMaxPixelsReader = _currentScrollMaxPixels;
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
      // 新手势重新记"翻面点"，别让上一段过渡的零点影响这一段的内容压暗。
      _handoffFlipMorph = null;
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
      // 目标位置是**页面坐标**的绝对值：多段时 tracker 已经把上游各段高度变化
      // 算了进去，这里再从当前像素累加差值会把它重复算一遍。
      final double? targetPixels =
          _viewportTracker.targetPixelsForLayer(targetLayer);
      // 上界**不夹取**，与点击档位那条路（`_applyTargets`）保持完全一致。
      //
      // 曾经这里按目标档位的 `maxScrollOffsetFor()` 夹取，那是个**单位错误**：
      // `maxScrollOffsetFor()` 返回的是 sliver 坐标（`内容总高 - 视口高`，且不含
      // 外层 `SliverPadding`），而 `_pinchTargetPixels` 是滚动像素 —— 两者相差
      // 一个外层 padding 加上尾部 padding。于是只要滚到列表底部，捏合的目标就被
      // 少算那么多：点击换档精确贴底，捏合却停在离底还差一截的位置。
      //
      // 越界交给本次布局的 `applyContentDimensions` 纠正，和点击路径同款处理。
      _pinchTargetPixels = math.max(0.0, targetPixels ?? _pinchBasePixels);
      _pinchTargetScale = pinch.targetZoomScale;
      zoomLog('pinch', () {
        return 'solve target=${zd(pinch.targetZoomScale, 3)} '
            'base=${zd(_pinchBasePixels)} '
            'baseSliver=${zd(_pinchBaseSliverOffset)} '
            'targetPage=${zd(targetPixels)} '
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
    if (_contentSide != 0 && _contentSide != side) {
      // 记下"真的换了布局"的那一帧的 morph。帧步进会越过阈值一截（实测
      // 0.525 → 0.406），光按距离阈值算的话这一帧的不透明度又会回到 0.37。
      _handoffFlipMorph = morph;
    }
    _contentSide = side;

    // 压暗的零点必须与**换布局的那一点**重合。
    //
    // 换布局发生在 `morph` 越过 0.45 / 0.55 的那一帧（滞回），两套内容排版
    // 结构不同（封面在上 / 封面在左、标题在封面下方 / 标题垂直居中），只能
    // 整份换、无法插值 —— 只要换的瞬间还看得见，条目内容就会"跳"一下。
    // 所以有两个零点：滞回带边界（提前淡出）和真实的翻面帧（兜住帧步进
    // 越过阈值的那个多走的量），取两者里更近的那个。
    final double bandHalf =
        (kFolderZoomContentHandoffUpper - kFolderZoomContentHandoffLower) * 0.5;
    double distance = math.max(0.0, (morph - 0.5).abs() - bandHalf);
    final double? flipMorph = _handoffFlipMorph;
    if (flipMorph != null) {
      distance = math.min(distance, (morph - flipMorph).abs());
    }
    final double reveal = distance >= kFolderZoomContentHandoffFadeHalfWindow
        ? 1.0
        : kFolderZoomContentHandoffMinOpacity +
              (1.0 - kFolderZoomContentHandoffMinOpacity) *
                  (distance / kFolderZoomContentHandoffFadeHalfWindow);
    return (isGrid: side > 0, reveal: reveal);
  }

  /// [FolderZoomSliverBuilder._resolveContentHandoff] 最近一次真正换布局时的 morph。
  double? _handoffFlipMorph;

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
    _pinchPinning = const <Object?, FolderZoomItemPinning>{};
    _pinchPinningFrom = null;
    _pinchPinningTo = null;
    _pinchPinningReady = false;
  }

  /// 取本次捏合要用的"单侧可见条目"冻结表；方向未判定时返回空表。
  ///
  /// 少了它，捏合全程只能走"所有条目按两端几何加权位移"这一条路：只在起始档位
  /// 可见的条目也会跟着插值上下漂，屏幕上就是「双指一捏，整屏条目一起移动」。
  /// 点击换档之所以没有这个现象，是因为它走 [_applyTargets] 那条路，里面有
  /// [FolderZoomViewportTracker.buildPinning] 把单侧条目锁在原地淡入淡出。
  Map<Object?, FolderZoomItemPinning> _resolvePinchPinning({
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
      return _pinchPinning;
    }
    if (_pinchPinningReady &&
        _pinchPinningFrom == from &&
        _pinchPinningTo == to) {
      return _pinchPinning;
    }

    // `mixLayers` 用**此刻屏幕上真实生效**的几何层：从点击换档的过渡动画中途
    // 接管时它就是那段动画的混合结果，锁在原位的参照系才是上一帧画出来的位置。
    final targetLayer = _layerOf(targetsTo, 1.0);
    final mixLayers = _effectiveGeometryLayers(_curved.value);
    final built = <Object?, FolderZoomItemPinning>{};
    for (final id in _viewportTracker.sectionIds) {
      final pinning = _viewportTracker.buildPinning(
        mixLayers: mixLayers,
        targetLayer: targetLayer,
        // 与布局侧 `_layerViewportTop(targetLayer)` 同一口径（含残差修正与夹取，
        // 夹取上界已包含 [tailExtent]）。淡入条目的锁定位置在 `progress = 0`
        // 处与目标位置严格相等，收尾（pinning 失效、单层接管）也不会弹一下。
        targetViewportTop: _viewportTracker.viewportTopForLayer(
          targetLayer,
          section: id,
          isPortrait: isPortrait,
        ),
        isPortrait: isPortrait,
        section: id,
      );
      if (pinning != null) built[id] = pinning;
    }
    _pinchPinning = built;
    _pinchPinningFrom = from;
    _pinchPinningTo = to;
    _pinchPinningReady = true;
    return _pinchPinning;
  }

  void _applyTargets(_ZoomTargets targets, {required bool animate}) {
    _targetCardWidth = targets.cardWidth;

    if (animate) {
      _selfHealBudget = 3;
      _handoffFlipMorph = null;
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
      // 目标滚动位置直接用**页面坐标**：tracker 已经把上游各段高度变化算进去了，
      // 不需要（也不能）再从当前像素累加一次差值。
      final double? targetPagePixels =
          _viewportTracker.targetPixelsForLayer(targetLayer);

      final position = _scrollPosition();
      if (position != null &&
          position.hasPixels &&
          _viewportTracker.isActiveInViewport) {
        final currentPixels = position.pixels;
        _startSliverOffset = _sliverTopForPixels(currentPixels);
        _startScrollPixels = currentPixels;
        _targetScrollPixels = targetPagePixels ?? currentPixels;
        _targetSliverOffset = _targetScrollPixels;
      } else {
        _startSliverOffset = _viewportTracker.viewportTop;
        _targetSliverOffset = targetPagePixels ?? _viewportTracker.viewportTop;
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
      //
      // 一页多个网格时按段各冻结一份：每段的条目索引都从 0 开始。
      final previousPinning = _controller.isAnimating
          ? _sectionPinning
          : const <Object?, FolderZoomItemPinning>{};
      final mixLayers = <FolderZoomGeometryLayer>[
        for (final entry in _geometryFrom) _layerOf(entry.targets, entry.weight),
      ];
      final built = <Object?, FolderZoomItemPinning>{};
      for (final id in tracker.sectionIds) {
        final pinning = tracker.buildPinning(
          mixLayers: mixLayers,
          targetLayer: targetLayer,
          targetViewportTop: tracker.viewportTopForLayer(
            targetLayer,
            section: id,
            isPortrait: isPortrait,
          ),
          isPortrait: isPortrait,
          section: id,
          previous: previousPinning[id],
          previousProgress: _curved.value,
        );
        if (pinning != null) built[id] = pinning;
      }
      _sectionPinning = built;

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
      _sectionPinning = const <Object?, FolderZoomItemPinning>{};
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
        )[null],
        sectionPinning: _pinchPinning,
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
      return FolderZoomMetricsScope(
        metrics: metrics,
        child: widget.builder(context, metrics),
      );
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
      itemPinning: _controller.isAnimating ? _sectionPinning[null] : null,
      sectionPinning: _controller.isAnimating
          ? _sectionPinning
          : const <Object?, FolderZoomItemPinning>{},
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
    return FolderZoomMetricsScope(
      metrics: metrics,
      child: widget.builder(context, metrics),
    );
  }
}

/// [SliverGridDelegate]：把条目摆到若干**确定**档位布局（[FolderZoomGeometryLayer]）
/// 的加权位置上。
class SliverAnimatedZoomGridDelegate extends SliverGridDelegate {
  const SliverAnimatedZoomGridDelegate({
    required this.metrics,
    this.section,
    this.listMainAxisSpacing = kFolderListRowSpacing,
    this.gridCrossAxisSpacing = kGridCrossAxisSpacing,
    this.gridMainAxisSpacing = kGridMainAxisSpacing,
  });

  final FolderZoomLayoutMetrics metrics;

  /// 本网格在页面里的身份，一页有多个网格时**必须各不相同**。
  ///
  /// 同一个 [FolderZoomSliverBuilder] 下挂几个网格时，滚动补偿要按"页面坐标"统一
  /// 结算：下游网格会随上游网格的高度变化整体平移，这个平移量只有把各段区分开才能
  /// 算对。留空表示"整页只有这一张网格"（行为与旧版完全一致）。
  ///
  /// 同一个 id 还要传给 [ZoomItemScaffold.section]，两边的条目索引才对得上。
  final Object? section;

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
        section: section,
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
      section: section,
      pinning: layers.length > 1 ? metrics.pinningFor(section) : null,
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
        oldDelegate.section != section ||
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
    this.section,
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

  /// 本网格所属的段；一页多网格时靠它取到自己那一份视口顶部与冻结表。
  final Object? section;

  /// 过渡开始时冻结的单侧可见条目处置表；见 [FolderZoomItemPinning]。
  final FolderZoomItemPinning? pinning;

  /// 本次过渡的线性进度，被锁定条目的收敛用。
  final double progress;

  bool get _hasSingleLayer => layers.length == 1;

  double _layerViewportTop(FolderZoomGeometryLayer layer) {
    if (tracker == null || !tracker!.hasMeasurement) return viewportTop;
    return tracker!.viewportTopForLayer(
      layer,
      section: section,
      isPortrait: isPortrait,
    );
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
            scrollOffset: _clampPinned(
              viewportTop + info.top,
              geometry.mainAxisExtent,
            ),
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
          scrollOffset: _clampPinned(viewportTop + top, geometry.mainAxisExtent),
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

  /// 把锁定条目的 sliver 坐标夹进本段的内容范围 `[0, 内容末端 - 条目高度]`。
  ///
  /// 单侧可见条目是锁在**屏幕**位置上的：`scrollOffset = viewportTop + 冻结的屏幕 y`。
  /// 这在屏幕上正是想要的（原地淡入淡出），但它是一个**跟着滚动位置走**的坐标：
  ///
  /// ```text
  /// 本段上报的高度 = 已布局条目里最靠下的那条的下边缘
  ///                = viewportTop + (冻结屏幕 y + 条目高度)
  ///                = (pixels - precede) + 常数
  /// ```
  ///
  /// `RenderSliverGrid` 正是这样取 `scrollExtent` / `paintExtent` 的（`reachedEnd`
  /// 时直接取 `trailingScrollOffset`），而视口里**后面每一个 sliver 的位置都是
  /// 前一个的 extent 累加出来的**（`layoutOffset += layoutExtent`）。于是本段之后
  /// 的内容——两段之间那行固定高的介绍、下一段网格——会被摆到一个"屏幕常量"的
  /// 位置上：换档过程中它们既不跟着插值移动，又在第一帧整体偏移一截，看起来就是
  /// "间隔那块组件位移动画消失，原地突然消失又出现"。
  ///
  /// 触发条件是本段**变矮**（列表→网格）且末尾几行有单侧可见条目：淡入条目锁在
  /// 目标档的屏幕位置上、高度也是目标档的（更矮的插值末端压不住它），它就成了
  /// 那条"最靠下的条目"。滚到上一段只剩半行的位置时最容易撞上。
  ///
  /// 夹回内容范围之后，最靠下的条目最多就是插值末端本身，本段报出去的高度重新
  /// 只取决于档位几何、与滚动位置无关；被挤出去的那点位移通常只有几十像素，且只
  /// 发生在正在淡入 / 淡出的条目上（不可见或正在消失）。
  double _clampPinned(double offset, double extent) {
    final int? count = tracker?.contentCountOf(section);
    if (count == null || count <= 0) return offset;
    double end = 0.0;
    for (final layer in layers) {
      end += _maxScrollOffsetIn(layer, count) * layer.weight;
    }
    final double maxOffset = math.max(0.0, end - extent);
    // 上界：不能越过内容末端；下界：不能高于内容起点（否则 `paintExtent` 的
    // `from` 会被拉到负值，同样把高度算多）。
    return offset.clamp(0.0, maxOffset);
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
    // 回填条目总数：tracker 要在换算目标档位的滚动偏移时按各档位的内容总高求解。
    tracker?.setContentCount(section, childCount);
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
