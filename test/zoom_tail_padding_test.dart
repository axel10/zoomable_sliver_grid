import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 回归：**尾部 padding（目录页底部避让浮动 Dock 的填充）不能把捏合首帧顶掉**。
///
/// 目录页的典型结构是 `banner + SliverPadding(top/bottom) + SliverGrid`，底部那一大块
/// padding 属于 `SliverPadding`、不属于本 sliver 的内容，所以：
/// - `contentExtentIn()` 算出来比真实可滚范围短；
/// - 文件夹不多时内容本身甚至比视口还矮（`内容总高 - 视口高` 是负数），
///   但页面照样能往下滚一百多像素。
///
/// 早期 `_recordAnchor()` 判"底部贴边"时要求 `maxScrollOffsetFor() > 0.5`
/// （内容必须比视口高），这种页面判不中，锚点落到 `none`；接着
/// `viewportTopForLayer()` 又把视口顶部夹回内容范围（`min(top, 内容总高 - 视口高)`），
/// 于是一进入捏合分支（第一帧），整屏条目按"视口顶部被夹掉的那一段"整体下移
/// —— 实测 18 个文件夹 + 底部 160 padding 时是 **146px**。
///
/// 现在：底端判据改成"内容末端进了视口"（不要求内容比视口高），
/// 而夹取上界补上了 `tailExtent`（稳态下由真实 `maxScrollExtent` 反推）。

class _Page extends StatefulWidget {
  const _Page({
    super.key,
    required this.initialZoom,
    required this.count,
    required this.bottomPadding,
    required this.scrollToEnd,
  });

  final double initialZoom;
  final int count;
  final double bottomPadding;
  final bool scrollToEnd;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final ScrollController controller = ScrollController();
  late double zoom = widget.initialZoom;
  FolderZoomLayoutMetrics? metrics;

  @override
  void initState() {
    super.initState();
    if (widget.scrollToEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!controller.hasClients) return;
        controller.jumpTo(controller.position.maxScrollExtent);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, c) {
            final content = FolderZoomSliverBuilder(
              zoomScale: zoom,
              width: c.maxWidth,
              builder: (context, m) {
                metrics = m;
                final hPad = folderContentHorizontalPadding(
                  isPortrait: m.isPortrait,
                  gridMorph: m.gridMorph,
                );
                final topPad = lerpDouble(0.0, 8.0, m.gridMorph)!;
                return CustomScrollView(
                  controller: controller,
                  slivers: [
                    const SliverToBoxAdapter(
                      child: SizedBox(
                        height: 220,
                        child: ColoredBox(color: Color(0xFF223344)),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.only(
                        top: topPad,
                        bottom: widget.bottomPadding,
                        left: hPad,
                        right: hPad,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: SliverAnimatedZoomGridDelegate(
                          metrics: m,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => ZoomItemScaffold(
                            key: ValueKey('item-$index'),
                            metrics: m,
                            titleText: 'Folder $index',
                            subtitleText: 'S$index',
                            infoText: '3:00',
                          ),
                          childCount: widget.count,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
            return ZoomGestureLayer(
              zoomScale: zoom,
              onZoomScaleChanged: (v) => setState(() => zoom = v),
              enableHaptics: false,
              child: content,
            );
          },
        ),
      ),
    );
  }
}

Map<int, double> _tops(WidgetTester tester, int count) {
  final tops = <int, double>{};
  for (var i = 0; i < count; i++) {
    final finder = find.byKey(ValueKey('item-$i'), skipOffstage: false);
    if (finder.evaluate().isEmpty) continue;
    tops[i] = tester.getRect(finder.first).top;
  }
  return tops;
}

Future<_PageState> _pump(
  WidgetTester tester, {
  required double zoom,
  required int count,
  required double bottomPadding,
  required bool scrollToEnd,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey<_PageState>();
  await tester.pumpWidget(
    _Page(
      key: key,
      initialZoom: zoom,
      count: count,
      bottomPadding: bottomPadding,
      scrollToEnd: scrollToEnd,
    ),
  );
  await tester.pumpAndSettle();
  await tester.pumpAndSettle();
  return key.currentState!;
}

/// 双指捏合缩小一档（栅格 → 列表），返回"静止帧"与"第一帧"的条目位置。
Future<({Map<int, double> settle, Map<int, double> first})> _pinch(
  WidgetTester tester,
  _PageState state,
  int count, {
  bool zoomIn = false,
}) async {
  final settle = _tops(tester, count);
  final g1 = await tester.startGesture(const Offset(150, 300), pointer: 11);
  final g2 = await tester.startGesture(const Offset(250, 400), pointer: 12);
  await tester.pump(const Duration(milliseconds: 16));
  final double d = zoomIn ? 6.0 : -6.0;
  await g1.moveTo(Offset(150 - d, 300 - d));
  await g2.moveTo(Offset(250 + d, 400 + d));
  await tester.pump(const Duration(milliseconds: 16));
  final first = _tops(tester, count);
  await g1.up();
  await g2.up();
  await tester.pumpAndSettle();
  return (settle: settle, first: first);
}

void _expectStill(
  Map<int, double> settle,
  Map<int, double> first,
  int index,
  String why,
) {
  final double? before = settle[index];
  final double? after = first[index];
  expect(before, isNotNull);
  expect(after, isNotNull);
  expect(
    (after! - before!).abs(),
    lessThan(8.0),
    reason: '$why：条目 $index 在捏合第一帧从 ${before.toStringAsFixed(1)} '
        '跳到 ${after.toStringAsFixed(1)}',
  );
}

void main() {
  testWidgets('内容比视口矮 + 底部 padding + 滚到底：锚定到底端，捏合首帧不位移', (tester) async {
    // 18 个文件夹 × 4 列 = 5 行，内容总高比 800 的视口还矮，
    // 页面可滚的 374px 全靠上方 228 的 banner 与下方 160 的 padding。
    final state = await _pump(
      tester,
      zoom: kFolderZoomTierSmallGrid,
      count: 18,
      bottomPadding: 160,
      scrollToEnd: true,
    );
    expect(
      state.metrics!.viewportTracker!.anchorEdgeName,
      'bottom',
      reason: '内容末端已经进了视口，锚点必须是底端；落到 none 会让夹取把内容顶掉一段',
    );

    final frame = await _pinch(tester, state, 18);
    // 底端锚定下，最后一行是"不动的那一行"，换档时只有它上面的内容在铺开。
    _expectStill(frame.settle, frame.first, 17, '底部 padding 场景');
  });

  testWidgets('内容比视口高 + 底部 padding + 滚到底：捏合首帧不位移', (tester) async {
    final state = await _pump(
      tester,
      zoom: kFolderZoomTierSmallGrid,
      count: 60,
      bottomPadding: 160,
      scrollToEnd: true,
    );
    expect(state.metrics!.viewportTracker!.anchorEdgeName, 'bottom');

    final frame = await _pinch(tester, state, 60);
    _expectStill(frame.settle, frame.first, 59, '长列表贴底场景');
  });

  testWidgets('没有底部 padding 时行为不变：贴底仍然锚定到底端', (tester) async {
    final state = await _pump(
      tester,
      zoom: kFolderZoomTierSmallGrid,
      count: 18,
      bottomPadding: 0,
      scrollToEnd: true,
    );
    expect(state.metrics!.viewportTracker!.anchorEdgeName, 'bottom');

    final frame = await _pinch(tester, state, 18);
    _expectStill(frame.settle, frame.first, 17, '无 padding 对照组');
  });

  testWidgets('贴底捏合放大（列表 → 栅格）：末端条目首帧不动', (tester) async {
    final state = await _pump(
      tester,
      zoom: kFolderZoomTierStandardList,
      count: 30,
      bottomPadding: 160,
      scrollToEnd: true,
    );
    expect(state.metrics!.viewportTracker!.anchorEdgeName, 'bottom');

    final frame = await _pinch(tester, state, 30, zoomIn: true);
    _expectStill(frame.settle, frame.first, 29, '贴底放大场景');
  });

  testWidgets('页面停在顶部时仍然锚定到顶端，首条不动', (tester) async {
    final state = await _pump(
      tester,
      zoom: kFolderZoomTierSmallGrid,
      count: 18,
      bottomPadding: 160,
      scrollToEnd: false,
    );
    expect(state.metrics!.viewportTracker!.anchorEdgeName, 'top');

    final frame = await _pinch(tester, state, 18);
    _expectStill(frame.settle, frame.first, 0, '顶部场景');
  });
}
