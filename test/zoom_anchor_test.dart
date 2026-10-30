import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 回归测试：换档时的滚动距离换算（焦点锚）。
///
/// 覆盖三个位置：顶部、中段、底部；两个方向。断言三件事：
/// 1. 过渡期间任何一帧都不能出现"视口内没有任何条目"（整屏空白）；
/// 2. 中段切换时，切换前后可见条目的交集不能明显缩水（共同可见条目尽量多）；
/// 3. 触顶 / 触底时最终滚动位置必须精确贴住 0 / maxScrollExtent。

class Harness extends StatefulWidget {
  const Harness({
    super.key,
    required this.initialZoom,
    this.count = 120,
    this.passController = true,
  });

  final double initialZoom;
  final int count;

  /// 是否把 controller 显式传给 [FolderZoomSliverBuilder]；
  /// `false` 时走"自动从渲染树里找 ScrollPosition"的兜底路径。
  final bool passController;

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
            return FolderZoomSliverBuilder(
              zoomScale: zoom,
              width: c.maxWidth,
              controller: widget.passController ? controller : null,
              builder: (context, metrics) {
                return CustomScrollView(
                  controller: controller,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: folderContentHorizontalPadding(
                          isPortrait: metrics.isPortrait,
                          gridMorph: metrics.gridMorph,
                        ),
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
                          childCount: widget.count,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Snapshot {
  _Snapshot({
    required this.pixels,
    required this.maxExtent,
    required this.visible,
  });

  final double pixels;
  final double maxExtent;

  /// 视口内可见条目的索引 -> 顶部 y。
  final Map<int, double> visible;

  bool get isEmpty => visible.isEmpty;
}

_Snapshot _snapshot(WidgetTester tester, ScrollController controller) {
  final visible = <int, double>{};
  for (var i = 0; i < 240; i++) {
    final finder = find.byKey(ValueKey('item-$i'), skipOffstage: false);
    if (finder.evaluate().isEmpty) continue;
    final rect = tester.getRect(finder.first);
    if (rect.bottom < 1 || rect.top > 799) continue;
    visible[i] = rect.top;
  }
  return _Snapshot(
    pixels: controller.offset,
    maxExtent: controller.position.maxScrollExtent,
    visible: visible,
  );
}

Future<HarnessState> _pump(
  WidgetTester tester, {
  required double initialZoom,
  bool passController = true,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey<HarnessState>();
  await tester.pumpWidget(
    Harness(
      key: key,
      initialZoom: initialZoom,
      passController: passController,
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

/// 跑完一次换档，返回每一帧的快照 + 稳态快照。
Future<List<_Snapshot>> _transition(
  WidgetTester tester,
  HarnessState state,
  double targetZoom,
) async {
  final frames = <_Snapshot>[];
  state.setZoom(targetZoom);
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    frames.add(_snapshot(tester, state.controller));
  }
  await tester.pumpAndSettle();
  frames.add(_snapshot(tester, state.controller));
  return frames;
}

void main() {
  testWidgets('中段 grid -> list：共同可见条目 >= 90%，且不出现空白帧', (tester) async {
    final state = await _pump(tester, initialZoom: kFolderZoomTierLargeGrid);
    final controller = state.controller;
    controller.jumpTo(controller.position.maxScrollExtent / 2);
    await tester.pumpAndSettle();

    final before = _snapshot(tester, controller);
    final frames = await _transition(tester, state, kFolderZoomTierStandardList);
    final after = frames.last;

    for (var i = 0; i < frames.length; i++) {
      expect(
        frames[i].isEmpty,
        isFalse,
        reason: '第 $i 帧视口内没有任何条目（整屏空白）',
      );
    }

    final shared = before.visible.keys
        .toSet()
        .intersection(after.visible.keys.toSet())
        .length;
    final smaller = before.visible.length < after.visible.length
        ? before.visible.length
        : after.visible.length;
    expect(
      shared,
      greaterThanOrEqualTo((smaller * 0.9).floor()),
      reason: '共同可见条目过少：before=${before.visible.keys.toList()} '
          'after=${after.visible.keys.toList()}',
    );
  });

  testWidgets('中段 list -> grid：共同可见条目 >= 90%，且不出现空白帧', (tester) async {
    final state = await _pump(
      tester,
      initialZoom: kFolderZoomTierStandardList,
    );
    final controller = state.controller;
    controller.jumpTo(controller.position.maxScrollExtent / 2);
    await tester.pumpAndSettle();

    final before = _snapshot(tester, controller);
    final frames = await _transition(tester, state, kFolderZoomTierLargeGrid);
    final after = frames.last;

    for (var i = 0; i < frames.length; i++) {
      expect(frames[i].isEmpty, isFalse, reason: '第 $i 帧整屏空白');
    }

    final shared = before.visible.keys
        .toSet()
        .intersection(after.visible.keys.toSet())
        .length;
    final smaller = before.visible.length < after.visible.length
        ? before.visible.length
        : after.visible.length;
    expect(
      shared,
      greaterThanOrEqualTo((smaller * 0.9).floor()),
      reason: '共同可见条目过少：before=${before.visible.keys.toList()} '
          'after=${after.visible.keys.toList()}',
    );
  });

  testWidgets('触底 list -> grid：最终精确贴底，且不出现空白帧', (tester) async {
    final state = await _pump(
      tester,
      initialZoom: kFolderZoomTierStandardList,
    );
    final controller = state.controller;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    final frames = await _transition(tester, state, kFolderZoomTierLargeGrid);
    for (var i = 0; i < frames.length; i++) {
      expect(frames[i].isEmpty, isFalse, reason: '第 $i 帧整屏空白');
    }
    expect(
      frames.last.pixels,
      closeTo(frames.last.maxExtent, 0.5),
      reason: '触底后应保持贴底',
    );
    expect(
      frames.last.visible.containsKey(119),
      isTrue,
      reason: '最后一条必须仍然可见',
    );
  });

  testWidgets('触底 grid -> list：最终精确贴底，且不出现空白帧', (tester) async {
    final state = await _pump(tester, initialZoom: kFolderZoomTierLargeGrid);
    final controller = state.controller;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    final frames = await _transition(tester, state, kFolderZoomTierMinimalList);
    for (var i = 0; i < frames.length; i++) {
      expect(frames[i].isEmpty, isFalse, reason: '第 $i 帧整屏空白');
    }
    expect(frames.last.pixels, closeTo(frames.last.maxExtent, 0.5));
    expect(frames.last.visible.containsKey(119), isTrue);
  });

  testWidgets('触顶换档：滚动位置保持 0', (tester) async {
    final state = await _pump(
      tester,
      initialZoom: kFolderZoomTierStandardList,
    );
    final frames = await _transition(tester, state, kFolderZoomTierLargeGrid);
    for (final frame in frames) {
      expect(frame.pixels, closeTo(0.0, 0.5));
    }
    expect(frames.last.visible.containsKey(0), isTrue);
  });

  testWidgets('不传 controller 时也能自动找到滚动位置并锚定', (tester) async {
    final state = await _pump(
      tester,
      initialZoom: kFolderZoomTierStandardList,
      passController: false,
    );
    final controller = state.controller;
    controller.jumpTo(controller.position.maxScrollExtent * 0.4);
    await tester.pumpAndSettle();

    final before = _snapshot(tester, controller);
    final frames = await _transition(tester, state, kFolderZoomTierLargeList);
    final after = frames.last;

    expect(after.pixels, isNot(closeTo(before.pixels, 0.5)),
        reason: '没有做滚动补偿时 offset 会原地不动');
    final shared = before.visible.keys
        .toSet()
        .intersection(after.visible.keys.toSet())
        .length;
    final smaller = before.visible.length < after.visible.length
        ? before.visible.length
        : after.visible.length;
    expect(shared, greaterThanOrEqualTo((smaller * 0.9).floor()));
  });

  testWidgets('双指捏合期间按手指位置重新取锚，不抛异常且会补偿滚动', (tester) async {
    final state = await _pump(
      tester,
      initialZoom: kFolderZoomTierStandardList,
    );
    final controller = state.controller;
    controller.jumpTo(controller.position.maxScrollExtent * 0.4);
    await tester.pumpAndSettle();
    final before = controller.offset;

    final g1 = await tester.startGesture(const Offset(480, 300), pointer: 11);
    final g2 = await tester.startGesture(const Offset(720, 500), pointer: 12);
    await tester.pump();

    // 双指分开 → 放大一档。
    for (var i = 0; i < 4; i++) {
      await g1.moveBy(const Offset(-40, -30));
      await g2.moveBy(const Offset(40, 30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.offset, isNot(closeTo(before, 0.5)),
        reason: '捏合换档后应按焦点换算滚动位置');
  });

  testWidgets('list -> list：焦点处的内容停在原高度', (tester) async {
    // 行距无空隙、索引一一对应，是检验"焦点不变量"最干净的一组档位。
    final state = await _pump(
      tester,
      initialZoom: kFolderZoomTierStandardList,
    );
    final controller = state.controller;
    controller.jumpTo(controller.position.maxScrollExtent * 0.4);
    await tester.pumpAndSettle();

    const focusY = 400.0;
    final before = _snapshot(tester, controller);
    final anchorIndex = before.visible.keys.firstWhere(
      (i) => before.visible[i]! <= focusY && before.visible[i]! + 80 > focusY,
      orElse: () => before.visible.keys.reduce(
        (a, b) => (before.visible[a]! - focusY).abs() <=
                (before.visible[b]! - focusY).abs()
            ? a
            : b,
      ),
    );
    final anchorTopBefore = before.visible[anchorIndex]!;

    final frames = await _transition(tester, state, kFolderZoomTierLargeList);
    final after = frames.last;
    for (var i = 0; i < frames.length; i++) {
      expect(frames[i].isEmpty, isFalse, reason: '第 $i 帧整屏空白');
    }
    expect(
      after.visible.containsKey(anchorIndex),
      isTrue,
      reason: '焦点条目 $anchorIndex 换档后应仍然可见 '
          '（before=${before.visible.keys.toList()} '
          'after=${after.visible.keys.toList()}）',
    );

    // 不变量是"焦点处的内容不动"，不是"条目顶部不动"：槽位从 80 拉到 104 时，
    // 条目顶部允许有 `r * Δ槽位` 的位移（≤ 24px），但焦点必须还落在它内部。
    final double topAfter = after.visible[anchorIndex]!;
    expect(
      topAfter,
      lessThanOrEqualTo(focusY),
      reason: '焦点条目顶部应仍在焦点上方：before=$anchorTopBefore after=$topAfter',
    );
    expect(
      topAfter + 104.0,
      greaterThan(focusY),
      reason: '焦点应仍落在焦点条目内部：after=$topAfter',
    );
    expect(
      (topAfter - anchorTopBefore).abs(),
      lessThan(30.0),
      reason: '焦点条目位移超过一个槽位增量：'
          'before=$anchorTopBefore after=$topAfter',
    );
  });
}
