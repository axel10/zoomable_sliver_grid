import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'zoom_layout_utils.dart';

/// 松手时的一次重排：`draggedIndices` 是被拖走的原始索引集合，
/// `insertIndex` 是「把这些条目按升序插进剩余列表的第几位之前」。
typedef ZoomReorderCallback = void Function(
  Set<int> draggedIndices,
  int insertIndex,
);

/// 自定义合集浮层外观；不传则用包内自带的 [ZoomReorderPreview]。
typedef ZoomReorderPreviewBuilder = Widget Function(
  BuildContext context,
  Set<int> draggedIndices,
  int count,
);

/// 为直接拖拽的条目生成系统级 [DragItem]（例如携带外部应用或队列抽屉能识别的数据）。
/// [selectedIndices] 为当前被一并拖拽的索引集合（若多选且当前项在已选列表中，则包含整组；否则仅包含当前项）。
/// [localData] 已预先注入了本网格的签名字段（`_zoom_grid_id`、`_zoom_index`、`_zoom_indices`）。
typedef ZoomItemDragItemBuilder = FutureOr<DragItem> Function(
  int index,
  Set<int> selectedIndices,
  Map<String, dynamic> localData,
);

/// 外部拖入或未匹配的数据在网格内松手时的回调。
typedef ZoomExternalDropCallback = void Function(
  PerformDropEvent event,
  int insertIndex,
);

/// 稳态档位下每个槽位的几何。
///
/// 与 [SliverAnimatedZoomGridDelegate] 用同一组常量和同一条公式
/// （见 `_SliverAnimatedZoomGridLayout.geometryInLayer`），所以网格态与列表态
/// 的槽位、行列步长、插入位判定都只有这一份实现。
///
/// 拖拽期间禁用换档，因此这里只取权重最大的**目标层**几何，不参与多档位加权插值。
class ZoomReorderGeometry {
  const ZoomReorderGeometry({
    required this.isGrid,
    required this.columns,
    required this.contentWidth,
    required this.cardWidth,
    required this.cardHeight,
    required this.listHeight,
    required this.mainStride,
    required this.crossStride,
    required this.listStride,
  });

  factory ZoomReorderGeometry.from(
    FolderZoomLayoutMetrics metrics,
    double width,
  ) {
    final layers = metrics.resolvedGeometryLayers;
    var layer = layers.first;
    for (final candidate in layers) {
      if (candidate.weight > layer.weight) layer = candidate;
    }
    final contentWidth = math.max(1.0, width);
    final listStride = layer.listExtent + kFolderListRowSpacing;

    if (!layer.isGrid) {
      return ZoomReorderGeometry(
        isGrid: false,
        columns: 1,
        contentWidth: contentWidth,
        cardWidth: contentWidth,
        cardHeight: layer.listExtent,
        listHeight: layer.listExtent,
        mainStride: listStride,
        crossStride: contentWidth,
        listStride: listStride,
      );
    }

    final columns = layer.crossAxisCount.clamp(1, 24).toInt();
    final cardWidth = FolderZoomPolicy.gridCardWidth(
      contentWidth: contentWidth,
      crossAxisCount: columns,
      crossAxisSpacing: kGridCrossAxisSpacing,
    );
    final cardHeight = cardWidth + layer.gridTextHeight;
    return ZoomReorderGeometry(
      isGrid: true,
      columns: columns,
      contentWidth: contentWidth,
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      listHeight: layer.listExtent,
      mainStride: cardHeight + kGridMainAxisSpacing,
      crossStride: cardWidth + kGridCrossAxisSpacing,
      listStride: listStride,
    );
  }

  final bool isGrid;
  final int columns;
  final double contentWidth;
  final double cardWidth;
  final double cardHeight;
  final double listHeight;
  final double mainStride;
  final double crossStride;
  final double listStride;

  Rect rectForSlot(int slot) {
    final safeSlot = slot < 0 ? 0 : slot;
    if (isGrid) {
      final row = safeSlot ~/ columns;
      final col = safeSlot % columns;
      return Rect.fromLTWH(
        col * crossStride,
        row * mainStride,
        cardWidth,
        cardHeight,
      );
    }
    return Rect.fromLTWH(0, safeSlot * listStride, contentWidth, listHeight);
  }

  /// 把指针在网格内容里的局部坐标换算成插入位。
  ///
  /// 网格态必须按「行 + 列」二维分别取整：`fy * columns + fx` 那种线性化会把
  /// 行内的垂直偏移也乘上列数 —— 8 列时鼠标明明在第 0 行，`fy=0.75` 就已经
  /// 贡献 6 个槽，避让框直接飞到最右列。列表态只有一维（等价于 columns=1），
  /// 仍按「越过行中心就插到下一行」四舍五入。
  int insertIndexFor(Offset local, int remainingCount) {
    final upper = math.max(0, remainingCount);
    if (!isGrid) {
      return (local.dy / listStride).round().clamp(0, upper).toInt();
    }
    final col = (local.dx / crossStride).floor().clamp(0, columns - 1);
    final row = math.max(0, (local.dy / mainStride).floor());
    return (row * columns + col).clamp(0, upper).toInt();
  }

  double contentHeightFor(int slotCount) {
    if (slotCount <= 0) return 0.0;
    if (isGrid) {
      final rows = (slotCount + columns - 1) ~/ columns;
      return math.max(0.0, rows * mainStride - kGridMainAxisSpacing);
    }
    return math.max(0.0, slotCount * listStride - kFolderListRowSpacing);
  }
}

/// 拖拽状态机。
///
/// 只管「谁被拖走、其余条目怎么补位、合集要避让哪个槽、松手回调什么」，
/// 不认识业务模型、不依赖 Riverpod / l10n / 数据库。
///
/// 拖动过程中**不修改数据**：原始索引始终不变，条目只是被映射到另一个槽位显示。
/// 松手后由调用方用 [applyReorder] 重排数据，映射结果正好等于重排后的顺序，
/// 因此动画能平滑收尾，不会先弹回原位再跳一次。
class ZoomReorderController extends ChangeNotifier {
  ZoomReorderController({this.placeholderCount = 1});

  /// 由 [ZoomReorderableSliverGrid] 每帧同步。
  ZoomReorderGeometry? geometry;
  int itemCount = 0;
  Set<int> selectedIndices = const <int>{};
  ZoomReorderCallback? onReorder;

  /// 合集在网格里占几个槽。列表态按需求压缩成 1 行，网格态默认也是 1 格。
  int placeholderCount;

  /// 不允许起拖的原始索引（例如固定首位的「系统媒体库」）。
  ///
  /// 这些条目仍留在 [_remaining] 里参与补位，只是永远不会被 [startDrag]
  /// 挑走；多选集合里也会先过滤掉它们。
  Set<int> lockedIndices = const <int>{};

  /// 插入位下限。锁定的条目若是列表前缀，把它设为前缀长度，
  /// 否则合集可以被插到固定项前面，调用方过滤掉固定项后顺序就错位了。
  int minInsertIndex = 0;

  /// 外部注入的坐标/滚动解析，包本身不持有页面结构。
  RenderBox? Function()? resolveBox;
  ScrollPosition? Function()? resolveScrollPosition;
  double? Function()? resolveViewportHeight;

  final ValueNotifier<Offset> pointer = ValueNotifier<Offset>(Offset.zero);
  final ValueNotifier<Set<int>> dragging =
      ValueNotifier<Set<int>>(const <int>{});

  /// 起拖瞬间，指针相对于被起拖条目左上角的局部偏移。
  /// 用于浮层对齐原位，避免浮层中心硬跳到指针上。
  Offset? grabOffset;

  /// 给 [ZoomGestureLayer] 的冻结闸：拖拽期间不吃捏合 / 滚轮缩放。
  final ValueNotifier<bool> reorderActive = ValueNotifier<bool>(false);

  int insertIndex = 0;
  List<int> _remaining = const <int>[];
  Timer? _autoScrollTimer;

  bool get isDragging => dragging.value.isNotEmpty;
  int get slotCount =>
      isDragging ? _remaining.length + placeholderCount : itemCount;

  /// 原始索引 → 显示槽位。返回 null 表示该条目正被拖走（浮层代替它）。
  int? displaySlotOf(int originalIndex) {
    if (dragging.value.contains(originalIndex)) return null;
    if (!isDragging) return originalIndex;
    final restIndex = _remaining.indexOf(originalIndex);
    if (restIndex < 0) return originalIndex;
    return restIndex < insertIndex
        ? restIndex
        : restIndex + placeholderCount;
  }

  void startDrag(int index, Offset globalPosition, {bool forceSingle = false}) {
    if (isDragging || index < 0 || index >= itemCount) return;
    if (lockedIndices.contains(index)) return;
    final selection = selectedIndices;
    final Set<int> picked;
    if (!forceSingle && selection.length > 1 && selection.contains(index)) {
      picked = selection
          .where((i) =>
              i >= 0 && i < itemCount && !lockedIndices.contains(i))
          .toSet();
    } else {
      picked = <int>{index};
    }
    if (picked.isEmpty) return;

    _remaining = <int>[
      for (var i = 0; i < itemCount; i++)
        if (!picked.contains(i)) i,
    ];
    // 合集初始停在它原来的位置附近，而不是直接跳到列表头。
    var at = index;
    for (final dragged in picked) {
      if (dragged < index) at--;
    }
    final lowerBound = minInsertIndex.clamp(0, _remaining.length);
    insertIndex = at.clamp(lowerBound, _remaining.length).toInt();

    final box = resolveBox?.call();
    final currentGeometry = geometry;
    if (box != null && box.attached && currentGeometry != null) {
      final localDown = box.globalToLocal(globalPosition);
      final itemRect = currentGeometry.rectForSlot(index);
      grabOffset = localDown - itemRect.topLeft;
    } else {
      grabOffset = null;
    }

    pointer.value = globalPosition;
    dragging.value = Set<int>.unmodifiable(picked);
    reorderActive.value = true;
    notifyListeners();
    _startAutoScroll();
  }

  void updateDrag(Offset globalPosition) {
    pointer.value = globalPosition;
    if (!isDragging) return;
    final currentGeometry = geometry;
    final box = resolveBox?.call();
    if (currentGeometry == null || box == null || !box.attached) return;
    final local = box.globalToLocal(globalPosition);
    final lowerBound = minInsertIndex.clamp(0, _remaining.length);
    final next = currentGeometry
        .insertIndexFor(local, _remaining.length)
        .clamp(lowerBound, _remaining.length)
        .toInt();
    if (next != insertIndex) {
      insertIndex = next;
      notifyListeners();
    }
  }

  void endDrag({bool commit = true}) {
    if (!isDragging) return;
    final picked = Set<int>.from(dragging.value);
    final at = insertIndex;
    _finishDrag();
    if (commit) onReorder?.call(picked, at);
  }

  void cancelDrag() => endDrag(commit: false);

  void _finishDrag() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    grabOffset = null;
    dragging.value = const <int>{};
    reorderActive.value = false;
    _remaining = const <int>[];
    notifyListeners();
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!isDragging) return;
      final position = resolveScrollPosition?.call();
      final viewportHeight = resolveViewportHeight?.call();
      if (position == null || viewportHeight == null || !position.hasPixels) {
        return;
      }
      const edge = 96.0;
      final dy = pointer.value.dy;
      var delta = 0.0;
      if (dy < edge) {
        delta = -math.max(4.0, (edge - dy) * 0.16);
      } else if (dy > viewportHeight - edge) {
        delta = math.max(4.0, (dy - (viewportHeight - edge)) * 0.16);
      }
      if (delta == 0.0) return;
      final target = (position.pixels + delta)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((target - position.pixels).abs() < 0.05) return;
      position.jumpTo(target);
      // 内容滚走了，同一个全局指针现在对应另一个槽，重算插入位。
      updateDrag(pointer.value);
    });
  }

  /// 调用方在 `onReorder` 里用它重排数据，保证与拖动时的映射完全一致。
  static List<T> applyReorder<T>(
    List<T> items,
    Set<int> draggedIndices,
    int insertIndex,
  ) {
    final sorted = draggedIndices
        .where((i) => i >= 0 && i < items.length)
        .toList()
      ..sort();
    if (sorted.isEmpty) return List<T>.from(items);
    final picked = <T>[for (final i in sorted) items[i]];
    final rest = <T>[
      for (var i = 0; i < items.length; i++)
        if (!draggedIndices.contains(i)) items[i],
    ];
    final at = insertIndex.clamp(0, rest.length).toInt();
    return <T>[...rest.take(at), ...picked, ...rest.skip(at)];
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    pointer.dispose();
    dragging.dispose();
    reorderActive.dispose();
    super.dispose();
  }
}

/// 让条目内的 [ZoomReorderHandle] 找到同一个状态机。
///
/// 刻意用普通 [InheritedWidget] 而不是 [InheritedNotifier]：手柄只需要拿到
/// controller 引用（调用方法），不需要随状态重建。若让手柄订阅一个跟
/// [ZoomReorderController] 同源的 InheritedNotifier，拖拽期每帧 notify 都会
/// 走 `notifyClients()`，在 `AnimatedBuilder` 重建的子树里容易触发
/// "dependent is not our descendant" 断言，且毫无收益。
class ZoomReorderScope extends InheritedWidget {
  const ZoomReorderScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final ZoomReorderController controller;

  static ZoomReorderController of(BuildContext context) {
    final element =
        context.getElementForInheritedWidgetOfExactType<ZoomReorderScope>();
    assert(element != null, 'ZoomReorderScope is missing above this widget.');
    return (element!.widget as ZoomReorderScope).controller;
  }

  @override
  bool updateShouldNotify(ZoomReorderScope oldWidget) =>
      oldWidget.controller != controller;
}

/// 手柄区域的占位 recognizer：按下即赢下手势竞技场。
///
/// 不处理任何手势，只负责让 [CustomScrollView] 的垂直拖拽抢不到这根 pointer。
/// 若让 Scrollable 赢，手势仲裁会把 pan 判负，`onPanUpdate` 从此停发、
/// `onPanCancel` 也未必送达，合集浮层就会冻在原地。位置更新改由 [Listener]
/// 直接吃 pointer 事件（不经过竞技场），因此也不可能再被抢断。
class _ZoomReorderHandleRecognizer extends OneSequenceGestureRecognizer {
  @override
  void addPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer);
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {}

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'zoom reorder handle';
}

/// 拖拽手柄。放在条目的右上角；在手柄上直接拖动即可起拖（鼠标 / 触屏都适用）。
///
/// 多选态下拖中已选条目会带走整个选中集合，否则只拖这一条。
///
/// 手势层**必须常驻**：起拖后该条目会被隐藏（opacity 0、由浮层代替），
/// 如果此时按 enabled 把手柄换成普通 Container，down 时缓存的命中路径就
/// 指向一个已卸载的 RenderObject，后续 move / up 全部丢失。
class ZoomReorderHandle extends StatefulWidget {
  const ZoomReorderHandle({
    super.key,
    required this.index,
    this.size = 30.0,
    this.enabled = true,
    this.child,
  });

  final int index;
  final double size;
  final bool enabled;
  final Widget? child;

  @override
  State<ZoomReorderHandle> createState() => _ZoomReorderHandleState();
}

class _ZoomReorderHandleState extends State<ZoomReorderHandle> {
  int? _pointer;
  Offset? _downGlobal;

  ZoomReorderController get _controller => ZoomReorderScope.of(context);

  void _onDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    _pointer = event.pointer;
    _downGlobal = event.position;
  }

  void _onMove(PointerMoveEvent event) {
    if (!widget.enabled || event.pointer != _pointer) return;
    final down = _downGlobal;
    if (down == null) return;
    final controller = _controller;
    if (!controller.isDragging) {
      // 保留一段 slop：点一下手柄不应立刻弹合集。
      if ((event.position - down).distance < kTouchSlop) return;
      controller.startDrag(widget.index, event.position);
    }
    controller.updateDrag(event.position);
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _downGlobal = null;
    // endDrag 幂等：即使只是点了一下、从未起拖，也不会提交空重排。
    _controller.endDrag();
  }

  void _onCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _downGlobal = null;
    _controller.cancelDrag();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handle = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(9.0),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.55),
        ),
      ),
      alignment: Alignment.center,
      child: widget.child ??
          Icon(
            Icons.drag_indicator_rounded,
            size: widget.size * 0.62,
            color: theme.colorScheme.primary,
          ),
    );
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        _ZoomReorderHandleRecognizer:
            GestureRecognizerFactoryWithHandlers<_ZoomReorderHandleRecognizer>(
          () => _ZoomReorderHandleRecognizer(),
          (_ZoomReorderHandleRecognizer instance) {},
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        child: handle,
      ),
    );
  }
}

/// 默认的「多条已集中成合集」浮层：堆叠卡片 + 数量角标。
class ZoomReorderPreview extends StatelessWidget {
  const ZoomReorderPreview({
    super.key,
    required this.count,
    this.size = const Size(120, 120),
    this.color,
  });

  final int count;
  final Size size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = color ?? theme.colorScheme.primary;
    final w = size.width * 0.78;
    final h = size.height * 0.78;
    return Opacity(
      opacity: 0.94,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (var layer = 2; layer >= 1; layer--)
            Positioned(
              left: (size.width - w) * 0.5 + layer * 7.0,
              top: (size.height - h) * 0.5 - layer * 7.0,
              child: Transform.rotate(
                angle: layer * 0.06,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: base.withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: base.withValues(alpha: 0.7)),
                  ),
                  child: SizedBox(width: w, height: h),
                ),
              ),
            ),
          Positioned(
            left: (size.width - w) * 0.5,
            top: (size.height - h) * 0.5,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(14),
              color: theme.colorScheme.surfaceContainerHighest,
              child: SizedBox(
                width: w,
                height: h,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.drag_indicator_rounded,
                          color: base, size: 26),
                      const SizedBox(height: 4),
                      Text(
                        '$count',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: base),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 可重排的缩放档位网格（第一阶段 demo 版）。
///
/// 网格态与列表态共用同一套槽位几何；拖动时余下条目自动填补空位、在插入位
/// 避让出合集槽；松手只回调一次 [onReorder]。
///
/// 实现说明：本阶段用 `SliverToBoxAdapter` + `Stack` + `AnimatedPositioned`
/// 全量摆放条目，换来零成本的补位/避让动画与精确的指针命中测试；接 vynody
/// 之前会换成懒加载的 `SliverGrid` 渲染层，[ZoomReorderController] 与
/// [ZoomReorderGeometry] 的接口保持不变。
class ZoomReorderableSliverGrid extends StatefulWidget {
  const ZoomReorderableSliverGrid({
    super.key,
    required this.metrics,
    required this.width,
    required this.itemCount,
    required this.itemBuilder,
    required this.onReorder,
    this.itemKeyBuilder,
    this.section,
    this.selectedIndices = const <int>{},
    this.lockedIndices = const <int>{},
    this.minInsertIndex = 0,
    this.enabled = true,
    this.showHandles = true,
    this.handleChild,
    this.placeholderCount = 1,
    this.previewBuilder,
    this.controller,
    this.animationDuration = const Duration(milliseconds: 220),
    this.enableDirectDrag = true,
    this.itemDragItemBuilder,
    this.directDragPreviewBuilder,
    this.dropIndicatorColor,
    this.dropIndicatorThickness = 3.0,
    this.onExternalDrop,
  });

  final FolderZoomLayoutMetrics metrics;
  final double width;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final ZoomReorderCallback onReorder;

  /// 为每个条目提供稳定的 [Key]。
  ///
  /// 重排后条目在列表中的下标（index）会改变。如果提供稳定的 Key（例如基于条目的业务 ID），
  /// Flutter 能在重排后精准匹配条目的 Element，彻底杜绝松手时被交换位置的条目
  /// 因复用拖拽项的 Element 而闪烁或发生非预期动画的问题。
  final Key? Function(int index)? itemKeyBuilder;

  /// 一页多段时的段身份，禁止跨段插入。
  final Object? section;

  /// 段内索引集合；拖中其中一条即带走整组。
  final Set<int> selectedIndices;

  /// 固定条目的原始索引：不显示可用手柄，也不能被拖走。
  final Set<int> lockedIndices;

  /// 插入位下限，用于保护 [lockedIndices] 中的前缀条目。
  final int minInsertIndex;
  final bool enabled;

  /// 多选模式下应设为 true：右上角出现拖拽手柄。
  final bool showHandles;

  /// 自定义手柄里的图标（不传用包内默认的 `drag_indicator_rounded`）。
  /// 容器背景 / 边框 / 命中区域仍由 [ZoomReorderHandle] 负责。
  final Widget? handleChild;
  final int placeholderCount;
  final ZoomReorderPreviewBuilder? previewBuilder;

  /// 可外部创建并同时喂给 [ZoomGestureLayer.reorderActive]。
  final ZoomReorderController? controller;
  final Duration animationDuration;

  /// 是否在非多选状态下允许鼠标直接在条目上按住起拖（基于系统拖拽，支持在列表内排序或拖出到外部目标）。
  final bool enableDirectDrag;

  /// 自定义条目直接拖拽时发布的系统级 [DragItem]（可携带文件路径或 URI 等，用于拖出到外部接收区）。
  final ZoomItemDragItemBuilder? itemDragItemBuilder;

  /// 条目直接拖拽时的浮动预览构建器。如果不传，单选默认展示条目快照，多选默认展示合集数量卡片。
  final Widget Function(BuildContext context, int index, Set<int> selectedIndices)?
      directDragPreviewBuilder;

  /// 高亮插入指示线颜色。
  final Color? dropIndicatorColor;

  /// 高亮插入指示线粗细（默认 3.0）。
  final double dropIndicatorThickness;

  /// 外部数据拖入并在指示线处释放时的回调。
  final ZoomExternalDropCallback? onExternalDrop;

  /// 是否支持系统级桌面拖拽（在测试环境或非桌面端平台自动禁用）。
  static bool get isNativeDragSupported {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  @override
  State<ZoomReorderableSliverGrid> createState() =>
      _ZoomReorderableSliverGridState();
}

class _ZoomReorderableSliverGridState
    extends State<ZoomReorderableSliverGrid> {
  late final ZoomReorderController _controller;
  late final bool _ownsController;
  late final String _gridId = 'zoom_grid_${identityHashCode(this)}';
  final GlobalKey _boxKey = GlobalKey();
  OverlayEntry? _overlay;
  OverlayState? _overlayState;

  int? _nativeDropInsertIndex;
  bool _isNativeDropOver = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ZoomReorderController();
    _controller.dragging.addListener(_onDraggingChanged);
  }

  @override
  void didUpdateWidget(covariant ZoomReorderableSliverGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      oldWidget.controller == widget.controller,
      'ZoomReorderableSliverGrid.controller must not change while mounted.',
    );
  }

  @override
  void dispose() {
    _controller.dragging.removeListener(_onDraggingChanged);
    _hideOverlay();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onDraggingChanged() {
    if (!mounted) return;
    if (_controller.isDragging && _overlay == null) {
      _showOverlay();
    } else if (!_controller.isDragging && _overlay != null) {
      _hideOverlay();
    }
  }

  void _showOverlay() {
    final overlay =
        Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.maybeOf(context);
    if (overlay == null) return;
    _overlayState = overlay;
    final entry = OverlayEntry(builder: _buildOverlay);
    _overlay = entry;
    overlay.insert(entry);
  }

  void _hideOverlay() {
    _overlay?.remove();
    _overlay = null;
    _overlayState = null;
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    return ValueListenableBuilder<Offset>(
      valueListenable: _controller.pointer,
      builder: (context, pointer, _) {
        final size = _controller.geometry?.rectForSlot(0).size ??
            const Size(120.0, 120.0);
        final overlayBox =
            _overlayState?.context.findRenderObject() as RenderBox?;
        final localPointer = overlayBox != null && overlayBox.attached
            ? overlayBox.globalToLocal(pointer)
            : pointer;
        final grab = _controller.grabOffset ??
            Offset(size.width * 0.5, size.height * 0.5);
        return Positioned(
          left: localPointer.dx - grab.dx,
          top: localPointer.dy - grab.dy,
          width: size.width,
          height: size.height,
          child: IgnorePointer(
            child: ValueListenableBuilder<Set<int>>(
              valueListenable: _controller.dragging,
              builder: (context, dragged, _) {
                return widget.previewBuilder
                        ?.call(context, dragged, dragged.length) ??
                    ZoomReorderPreview(count: dragged.length, size: size);
              },
            ),
          ),
        );
      },
    );
  }

  void _syncController(ZoomReorderGeometry geometry) {
    _controller.geometry = geometry;
    _controller.itemCount = widget.itemCount;
    _controller.selectedIndices = widget.selectedIndices;
    _controller.lockedIndices = widget.lockedIndices;
    _controller.minInsertIndex = widget.minInsertIndex;
    _controller.placeholderCount = widget.placeholderCount;
    _controller.onReorder = widget.enabled ? widget.onReorder : null;
    _controller.resolveBox = () {
      final boxContext = _boxKey.currentContext;
      if (boxContext == null) return null;
      final object = boxContext.findRenderObject();
      return object is RenderBox && object.attached ? object : null;
    };
    _controller.resolveScrollPosition = () =>
        Scrollable.maybeOf(context)?.position;
    _controller.resolveViewportHeight = () => MediaQuery.sizeOf(context).height;
  }

  FutureOr<DropOperation> _handleNativeDropOver(
    DropOverEvent event,
    ZoomReorderGeometry geometry,
  ) {
    final local = event.position.local;
    final insertIndex = geometry.insertIndexFor(local, widget.itemCount);

    if (_nativeDropInsertIndex != insertIndex) {
      setState(() {
        _nativeDropInsertIndex = insertIndex;
        _isNativeDropOver = true;
      });
    }

    final localData = event.session.items.firstOrNull?.localData;
    if (localData is Map && localData['_zoom_grid_id'] == _gridId) {
      return DropOperation.move;
    }
    return DropOperation.copy;
  }

  void _clearNativeDrop() {
    if (_nativeDropInsertIndex != null || _isNativeDropOver) {
      setState(() {
        _nativeDropInsertIndex = null;
        _isNativeDropOver = false;
      });
    }
  }

  Future<void> _handleNativePerformDrop(PerformDropEvent event) async {
    final targetIndex = _nativeDropInsertIndex;
    _clearNativeDrop();
    if (targetIndex == null) return;

    final firstItem = event.session.items.firstOrNull;
    final localData = firstItem?.localData;

    if (localData is Map && localData['_zoom_grid_id'] == _gridId) {
      final draggedIndicesRaw = localData['_zoom_indices'];
      final Set<int> draggedIndices;
      if (draggedIndicesRaw is List) {
        draggedIndices = draggedIndicesRaw.cast<int>().toSet();
      } else {
        final draggedIndex = localData['_zoom_index'];
        draggedIndices = draggedIndex is int ? {draggedIndex} : <int>{};
      }
      if (draggedIndices.isNotEmpty) {
        widget.onReorder(draggedIndices, targetIndex);
        return;
      }
    }

    widget.onExternalDrop?.call(event, targetIndex);
  }

  @override
  Widget build(BuildContext context) {
    final geometry = ZoomReorderGeometry.from(widget.metrics, widget.width);
    _syncController(geometry);

    final showDirectDrag = widget.enabled &&
        widget.enableDirectDrag &&
        ZoomReorderableSliverGrid.isNativeDragSupported &&
        !_controller.isDragging;

    final content = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final slotCount = _controller.slotCount;
        final height = math.max(1.0, geometry.contentHeightFor(slotCount));
        return SizedBox(
          key: _boxKey,
          width: widget.width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              for (var i = 0; i < widget.itemCount; i++)
                _buildItem(context, i, geometry, showDirectDrag),
              if (_controller.isDragging) _buildPlaceholder(geometry),
              if (_nativeDropInsertIndex != null)
                _buildNativeDropIndicator(geometry),
            ],
          ),
        );
      },
    );

    final sliverChild = (ZoomReorderableSliverGrid.isNativeDragSupported &&
            (showDirectDrag || widget.onExternalDrop != null))
        ? DropRegion(
            formats: Formats.standardFormats,
            hitTestBehavior: HitTestBehavior.opaque,
            onDropOver: (event) => _handleNativeDropOver(event, geometry),
            onDropLeave: (event) => _clearNativeDrop(),
            onDropEnded: (event) => _clearNativeDrop(),
            onPerformDrop: (event) => _handleNativePerformDrop(event),
            child: content,
          )
        : content;

    return ZoomReorderScope(
      controller: _controller,
      child: SliverToBoxAdapter(
        child: sliverChild,
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    int index,
    ZoomReorderGeometry geometry,
    bool showDirectDrag,
  ) {
    final slot = _controller.displaySlotOf(index);
    final hidden = slot == null;
    final int effectiveSlot;
    if (slot != null) {
      effectiveSlot = slot;
    } else {
      final dragged = _controller.dragging.value.toList()..sort();
      final rank = dragged.indexOf(index);
      effectiveSlot = rank >= 0 ? _controller.insertIndex + rank : index;
    }
    final rect = geometry.rectForSlot(effectiveSlot);
    // 拖拽期间即使外部把 showHandles 关掉，也必须保留手柄层：起拖条目的
    // pointer 命中路径是在 down 时缓存的，换成别的 widget 会丢掉后续 move。
    final showHandle = widget.enabled &&
        !widget.lockedIndices.contains(index) &&
        (widget.showHandles || _controller.isDragging);
    final itemKey = widget.itemKeyBuilder?.call(index) ?? ValueKey<int>(index);

    Widget innerChild = widget.itemBuilder(context, index);

    if (showDirectDrag && !widget.lockedIndices.contains(index)) {
      final isPartSelected = widget.selectedIndices.contains(index);
      final pickedIndices = isPartSelected && widget.selectedIndices.length > 1
          ? widget.selectedIndices
              .where((i) => !widget.lockedIndices.contains(i))
              .toSet()
          : <int>{index};

      innerChild = DragItemWidget(
        allowedOperations: () => const [DropOperation.move, DropOperation.copy],
        dragItemProvider: (request) async {
          final local = <String, dynamic>{
            '_zoom_grid_id': _gridId,
            '_zoom_index': index,
            '_zoom_indices': pickedIndices.toList(),
          };
          DragItem? item;
          if (widget.itemDragItemBuilder != null) {
            item = await widget.itemDragItemBuilder!(
              index,
              pickedIndices,
              local,
            );
          }
          item ??= DragItem(localData: local);
          if (item.localData is Map) {
            final map = item.localData as Map;
            map['_zoom_grid_id'] = _gridId;
            map['_zoom_index'] = index;
            map['_zoom_indices'] = pickedIndices.toList();
          }
          return item;
        },
        dragBuilder: (context, child) {
          if (widget.directDragPreviewBuilder != null) {
            return widget.directDragPreviewBuilder!(
              context,
              index,
              pickedIndices,
            );
          }
          if (pickedIndices.length > 1) {
            return ZoomReorderPreview(
              count: pickedIndices.length,
              size: rect.size,
            );
          }
          return Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(10),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: SizedBox(
              width: rect.width,
              height: rect.height,
              child: Opacity(
                opacity: 0.92,
                child: widget.itemBuilder(context, index),
              ),
            ),
          );
        },
        child: DraggableWidget(
          hitTestBehavior: HitTestBehavior.translucent,
          child: innerChild,
        ),
      );
    }

    return AnimatedPositioned(
      key: itemKey,
      duration: widget.animationDuration,
      curve: Curves.easeOutCubic,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Opacity(
        opacity: hidden ? 0.0 : 1.0,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned.fill(
              // 被拖走的条目只是变透明；屏蔽内容区的幽灵点击，
              // 但手柄挂在 Stack 外层，不受影响（拖拽链路要靠它续命）。
              child: IgnorePointer(
                ignoring: hidden,
                child: innerChild,
              ),
            ),
            if (showHandle)
              Positioned(
                top: 4.0,
                right: 4.0,
                child: ZoomReorderHandle(
                  index: index,
                  child: widget.handleChild,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNativeDropIndicator(ZoomReorderGeometry geometry) {
    final insertIndex = _nativeDropInsertIndex;
    if (insertIndex == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final color = widget.dropIndicatorColor ?? theme.colorScheme.primary;
    final thickness = widget.dropIndicatorThickness;

    if (!geometry.isGrid) {
      final double top;
      if (insertIndex <= 0) {
        top = 0.0;
      } else if (insertIndex >= widget.itemCount) {
        top = geometry.contentHeightFor(widget.itemCount) - thickness;
      } else {
        top = insertIndex * geometry.listStride -
            kFolderListRowSpacing * 0.5 -
            thickness * 0.5;
      }

      return Positioned(
        key: const ValueKey<String>('zoom-native-drop-indicator'),
        left: 0,
        right: 0,
        top: top,
        height: thickness,
        child: IgnorePointer(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4.0),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.55),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final clampedSlot = insertIndex.clamp(0, widget.itemCount);
    final rect = geometry.rectForSlot(clampedSlot);
    final isEndOfRow = geometry.columns > 1 && clampedSlot == widget.itemCount;
    final left = isEndOfRow
        ? rect.left + rect.width + (kGridCrossAxisSpacing * 0.5) - (thickness * 0.5)
        : rect.left - (kGridCrossAxisSpacing * 0.5) - (thickness * 0.5);

    return Positioned(
      key: const ValueKey<String>('zoom-native-drop-indicator'),
      left: math.max(0.0, left),
      top: rect.top,
      width: thickness,
      height: rect.height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.55),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ZoomReorderGeometry geometry) {
    final rect = geometry.rectForSlot(_controller.insertIndex);
    final theme = Theme.of(context);
    return AnimatedPositioned(
      key: const ValueKey<String>('zoom-reorder-placeholder'),
      duration: widget.animationDuration,
      curve: Curves.easeOutCubic,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.75),
              width: 2.0,
            ),
          ),
        ),
      ),
    );
  }
}
