import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 回归测试：缩放列表上方还有别的组件（header / 吸顶条 / 外层 padding）时，
/// 列表起始位置**不在视口顶端**，锚定与滚动补偿必须照常工作。
///
/// 背景：`SliverConstraints.scrollOffset` 在"列表起始边还在视口顶端之下"时会被
/// Flutter 钳在 0（`RenderViewportBase.layoutChildSequence`），早期实现直接拿它当
/// 视口顶部，于是把这种状态误判成"列表已贴顶"：换档 / 捏合直接跳过滚动补偿
/// （日志 `skip: no scroll delta`），内容只在原地往下长；连 `viewportHeight` 都被
/// 误算成 `remainingPaintExtent`（被 header 吃掉一截）。
///
/// 覆盖四种布局 × 三个滚动位置（页面顶端 / 中段 / 贴底）。

enum HeaderKind { none, scrolling, pinned }

class _FixedHeaderDelegate extends SliverPersistentHeaderDelegate {
  _FixedHeaderDelegate({required this.extent});

  final double extent;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(color: const Color(0xFF884444));
  }

  @override
  bool shouldRebuild(_FixedHeaderDelegate oldDelegate) =>
      oldDelegate.extent != extent;
}

class Harness extends StatefulWidget {
  const Harness({
    super.key,
    required this.headerKind,
    this.headerHeight = 400,
    this.initialZoom = kFolderZoomTierStandardList,
    this.withGestureLayer = false,
  });

  final HeaderKind headerKind;
  final double headerHeight;
  final double initialZoom;
  final bool withGestureLayer;

  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  final ScrollController controller = ScrollController();
  late double zoom = widget.initialZoom;

  void setZoom(double value) => setState(() => zoom = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, c) {
            final content = FolderZoomSliverBuilder(
              zoomScale: zoom,
              width: c.maxWidth,
              controller: controller,
              builder: (context, metrics) {
                return CustomScrollView(
                  controller: controller,
                  slivers: [
                    switch (widget.headerKind) {
                      HeaderKind.none => const SliverToBoxAdapter(
                          child: SizedBox.shrink(),
                        ),
                      HeaderKind.scrolling => SliverToBoxAdapter(
                          child: SizedBox(height: widget.headerHeight),
                        ),
                      HeaderKind.pinned => SliverPersistentHeader(
                          pinned: true,
                          delegate: _FixedHeaderDelegate(
                            extent: widget.headerHeight,
                          ),
                        ),
                    },
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: SliverAnimatedZoomGridDelegate(
                          metrics: metrics,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => ZoomItemScaffold(
                            key: ValueKey('item-$index'),
                            metrics: metrics,
                            titleText: 'Item $index',
                            subtitleText: 'S$index',
                            infoText: '3:00',
                          ),
                          childCount: 120,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
            if (!widget.withGestureLayer) return content;
            return ZoomGestureLayer(
              zoomScale: zoom,
              onZoomScaleChanged: setZoom,
              child: content,
            );
          },
        ),
      ),
    );
  }
}

const double _screenHeight = 800.0;
const double _focusY = 400.0;

Map<int, Rect> _rects(WidgetTester tester) {
  final rects = <int, Rect>{};
  for (var i = 0; i < 120; i++) {
    final finder = find.byKey(ValueKey('item-$i'), skipOffstage: false);
    if (finder.evaluate().isEmpty) continue;
    final rect = tester.getRect(finder.first);
    if (rect.bottom < 1 || rect.top > _screenHeight - 1) continue;
    rects[i] = rect;
  }
  return rects;
}

/// 焦点高度处的内容：返回 (条目索引, 焦点落在条目内的比例)。
(int, double) _focusContent(Map<int, Rect> rects) {
  for (final entry in rects.entries) {
    final rect = entry.value;
    if (rect.top <= _focusY && rect.bottom > _focusY) {
      return (entry.key, (rect.height <= 1) ? 0.0 : (_focusY - rect.top) / rect.height);
    }
  }
  final nearest = rects.keys.reduce(
    (a, b) => (rects[a]!.top - _focusY).abs() <= (rects[b]!.top - _focusY).abs()
        ? a
        : b,
  );
  return (nearest, 0.0);
}

Future<HarnessState> _pump(
  WidgetTester tester, {
  required HeaderKind kind,
  double headerHeight = 400,
  bool withGestureLayer = false,
}) async {
  tester.view.physicalSize = const Size(400, _screenHeight);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey<HarnessState>();
  await tester.pumpWidget(
    Harness(
      key: key,
      headerKind: kind,
      headerHeight: headerHeight,
      withGestureLayer: withGestureLayer,
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

Future<void> _settleZoom(WidgetTester tester, HarnessState state, double zoom) async {
  state.setZoom(zoom);
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

void main() {
  group('列表上方有可滚走的 header', () {
    // 全部落在"header 还没滚出视口"的区间内（header 400 + padding 16）：
    // 这正是 `scrollOffset` 被钳在 0、早期实现误判成"已贴顶"的窗口。
    for (final startPixels in <double>[100, 200, 340]) {
      testWidgets('header 仍在视口内（px=$startPixels）换档要补偿滚动，'
          '焦点处的内容必须留在焦点处', (tester) async {
        final state = await _pump(tester, kind: HeaderKind.scrolling);
        state.controller.jumpTo(startPixels);
        await tester.pumpAndSettle();

        final before = _rects(tester);
        final pixelsBefore = state.controller.offset;
        final (anchorIndex, _) = _focusContent(before);
        // 前置条件：焦点确实落在某条内容上（否则这条用例没有意义）。
        expect(
          before[anchorIndex]!.top <= _focusY &&
              before[anchorIndex]!.bottom > _focusY,
          isTrue,
          reason: '焦点本该落在条目 #$anchorIndex 内：${before[anchorIndex]}',
        );

        await _settleZoom(tester, state, kFolderZoomTierLargeList);

        final after = _rects(tester);
        expect(tester.takeException(), isNull);

        // 关键点 1：换档**必须**补偿滚动。早期实现把这种状态当成"已贴顶"，
        // pixels 一点不动，内容只在原地往下长。
        expect(
          state.controller.offset,
          isNot(closeTo(pixelsBefore, 0.5)),
          reason: '换档没有补偿滚动（pixels 原地不动）：'
              '列表起始边不在视口顶端这种布局没被适配',
        );

        // 关键点 2：焦点处的内容换档后仍在焦点处（焦点不变量）。
        expect(
          after.containsKey(anchorIndex),
          isTrue,
          reason: '焦点条目 #$anchorIndex 换档后不见了：'
              'before=${before.keys.toList()} after=${after.keys.toList()}',
        );
        expect(
          after[anchorIndex]!.top,
          lessThanOrEqualTo(_focusY),
          reason: '焦点条目 #$anchorIndex 被推到焦点下方：'
              'before=${before[anchorIndex]} after=${after[anchorIndex]}',
        );
        expect(
          after[anchorIndex]!.bottom,
          greaterThan(_focusY),
          reason: '焦点条目 #$anchorIndex 被拉到焦点上方：'
              'before=${before[anchorIndex]} after=${after[anchorIndex]}',
        );
      });
    }

    testWidgets('页面最顶端换档：滚动位置保持 0，不会往下跳一整个 header', (tester) async {
      final state = await _pump(tester, kind: HeaderKind.scrolling);
      expect(state.controller.offset, closeTo(0.0, 0.5));

      await _settleZoom(tester, state, kFolderZoomTierLargeList);
      expect(
        state.controller.offset,
        closeTo(0.0, 0.5),
        reason: '页面最顶端换档把页面往下拽了：${state.controller.offset}',
      );

      // 列表起始边本来就贴在 header 下方，锚定后仍应停在同一高度。
      final first = _rects(tester)[0];
      expect(first, isNotNull, reason: '首条目丢了');
      expect(first!.top, closeTo(400 + 16, 1.0));
    });

    testWidgets('贴底换档：精确贴住 maxScrollExtent，最后一条可见', (tester) async {
      final state = await _pump(tester, kind: HeaderKind.scrolling);
      state.controller.jumpTo(state.controller.position.maxScrollExtent);
      await tester.pumpAndSettle();

      await _settleZoom(tester, state, kFolderZoomTierLargeGrid);
      expect(
        state.controller.offset,
        closeTo(state.controller.position.maxScrollExtent, 0.5),
        reason: '带 header 时贴底换档不再贴底',
      );
      expect(_rects(tester).containsKey(119), isTrue);
    });
  });

  group('吸顶 header（pinned）', () {
    testWidgets('中段换档：焦点内容不被甩走，且照常补偿滚动', (tester) async {
      final state = await _pump(
        tester,
        kind: HeaderKind.pinned,
        headerHeight: 56,
      );
      final max = state.controller.position.maxScrollExtent;
      state.controller.jumpTo(max * 0.4);
      await tester.pumpAndSettle();

      final before = _rects(tester);
      final pixelsBefore = state.controller.offset;
      final (anchorIndex, _) = _focusContent(before);

      await _settleZoom(tester, state, kFolderZoomTierLargeList);

      final after = _rects(tester);
      expect(after.containsKey(anchorIndex), isTrue);
      expect(
        after[anchorIndex]!.top,
        closeTo(before[anchorIndex]!.top, 40.0),
        reason: '吸顶 header 下焦点条目位移过大：'
            'before=${before[anchorIndex]!.top} after=${after[anchorIndex]!.top}',
      );
      expect(state.controller.offset, isNot(closeTo(pixelsBefore, 0.5)));
    });

    testWidgets('贴底换档：精确贴住 maxScrollExtent', (tester) async {
      final state = await _pump(
        tester,
        kind: HeaderKind.pinned,
        headerHeight: 56,
      );
      state.controller.jumpTo(state.controller.position.maxScrollExtent);
      await tester.pumpAndSettle();

      await _settleZoom(tester, state, kFolderZoomTierLargeGrid);
      expect(
        state.controller.offset,
        closeTo(state.controller.position.maxScrollExtent, 0.5),
        reason: '吸顶 header 下贴底换档不再贴底',
      );
      expect(_rects(tester).containsKey(119), isTrue);
    });
  });

  /// 捏合走的是另一条补偿路径（`_sliverTopForPixels` + 每帧 `jumpTo`）：
  /// 早期实现里它会把 pixels 拽回"上一帧布局时的值"，表现是手指在捏、列表却僵住。
  testWidgets('header 还在视口内时双指捏合：滚动跟着补偿，焦点条目不被甩出视口', (tester) async {
    final state = await _pump(
      tester,
      kind: HeaderKind.scrolling,
      withGestureLayer: true,
    );
    state.controller.jumpTo(200);
    await tester.pumpAndSettle();

    final pixelsBefore = state.controller.offset;
    final before = _rects(tester);
    final (anchorIndex, _) = _focusContent(before);

    final g1 = await tester.startGesture(const Offset(150, 300), pointer: 21);
    final g2 = await tester.startGesture(const Offset(250, 400), pointer: 22);
    await tester.pump(const Duration(milliseconds: 16));

    for (var step = 1; step <= 6; step++) {
      final d = step * 6.0;
      await g1.moveTo(Offset(150 - d, 300 - d));
      await g2.moveTo(Offset(250 + d, 400 + d));
      await tester.pump(const Duration(milliseconds: 16));

      final frame = _rects(tester);
      expect(
        frame.containsKey(anchorIndex),
        isTrue,
        reason: '第 $step 步焦点条目 #$anchorIndex 被甩出视口',
      );
    }

    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      state.controller.offset,
      isNot(closeTo(pixelsBefore, 0.5)),
      reason: '捏合换档没有补偿滚动（pixels 原地不动）',
    );
  });

  testWidgets('无 header 的基准行为不变：顶部保持 0、中段照旧补偿', (tester) async {
    final state = await _pump(tester, kind: HeaderKind.none);
    await _settleZoom(tester, state, kFolderZoomTierLargeList);
    expect(state.controller.offset, closeTo(0.0, 0.5));

    final max = state.controller.position.maxScrollExtent;
    state.controller.jumpTo(max * 0.4);
    await tester.pumpAndSettle();
    final pixelsBefore = state.controller.offset;
    await _settleZoom(tester, state, kFolderZoomTierMediumGrid);
    expect(state.controller.offset, isNot(closeTo(pixelsBefore, 0.5)));
  });
}
