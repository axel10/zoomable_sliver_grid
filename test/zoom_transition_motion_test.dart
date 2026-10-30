import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 回归测试：换档过渡期间条目的运动必须是**单调**的。
///
/// 曾经的实现在布局里按"该条目在某一层视口内是否可见"分支：
/// 两层都可见走加权混合，只有一层可见就锁死到那一层的屏幕位置。可见性是布尔量，
/// 而过渡期滚动位置要在几千像素上平移，条目会反复翻转可见性，每翻转一次位置就在
/// "混合值"和"层锁定值"之间瞬移一次 —— 观感就是所有条目一起"从下往上弹一下"。
///
/// 另外 `_onTick` 曾经用上一帧的 `maxScrollExtent` 夹取插值位置：触底换档时内容
/// 每帧要长上千像素，滚动因此永远慢一帧，条目先被画低、下一帧再被拽回，同样是
/// "弹一下"的来源。
///
/// 所以这里断言的不是"最终落点"，而是**过程**：任何一条可见条目在任何一帧都
/// 不允许出现反向位移。

const int _kItemCount = 120;

class _Harness extends StatefulWidget {
  const _Harness({super.key, required this.initialZoom});

  final double initialZoom;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
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
              controller: controller,
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
                          childCount: _kItemCount,
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

/// 单帧快照：条目索引 -> 屏幕顶部 y。
typedef _Frame = Map<int, double>;

_Frame _frame(WidgetTester tester) {
  final tops = <int, double>{};
  for (var i = 0; i < _kItemCount; i++) {
    final finder = find.byKey(ValueKey('item-$i'), skipOffstage: false);
    if (finder.evaluate().isEmpty) continue;
    tops[i] = tester.getRect(finder.first).top;
  }
  return tops;
}

Future<_HarnessState> _pump(
  WidgetTester tester, {
  required Size size,
  required double initialZoom,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(_Harness(key: key, initialZoom: initialZoom));
  await tester.pumpAndSettle();
  return key.currentState!;
}

/// 跑完一次换档，返回逐帧快照。
Future<List<_Frame>> _transition(
  WidgetTester tester,
  _HarnessState state,
  double targetZoom,
) async {
  final frames = <_Frame>[];
  state.setZoom(targetZoom);
  for (var i = 0; i < 18; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    frames.add(_frame(tester));
  }
  await tester.pumpAndSettle();
  frames.add(_frame(tester));
  return frames;
}

/// 断言：每个条目的屏幕位置在过渡期间**单调**变化。
///
/// 方向不预设——触底换档时条目往哪边走取决于该档位下内容总高变大还是变小，
/// 与"放大 / 缩小"没有固定关系。所以按每个条目自身的净位移取方向，只校验
/// 中途不出现反向折返（这正是"弹一下"的特征）。
///
/// 允许 [tolerance] 的抖动（字号量化、几何四舍五入会带来亚像素误差）。
void _expectMonotonic(
  List<_Frame> frames, {
  double tolerance = 1.5,
}) {
  final indices = <int>{
    for (final frame in frames) ...frame.keys,
  };
  for (final index in indices) {
    final samples = <({int frame, double top})>[];
    for (var f = 0; f < frames.length; f++) {
      final top = frames[f][index];
      if (top != null) samples.add((frame: f, top: top));
    }
    if (samples.length < 3) continue;

    final double net = samples.last.top - samples.first.top;
    if (net.abs() <= 2.0) continue; // 几乎没动的条目（贴着锚点）不参与校验
    final bool upward = net < 0;

    for (var i = 1; i < samples.length; i++) {
      final previous = samples[i - 1];
      final current = samples[i];
      // 只比较相邻两帧：跨帧比较会把"条目离开/进入构建范围"也算进来。
      if (current.frame != previous.frame + 1) continue;
      final double delta = current.top - previous.top;
      final bool reversed = upward ? delta > tolerance : delta < -tolerance;
      expect(
        reversed,
        isFalse,
        reason: '条目 $index 在第 ${current.frame} 帧反向位移 '
            '${delta.toStringAsFixed(1)}px（上一帧 ${previous.top.toStringAsFixed(1)} '
            '→ ${current.top.toStringAsFixed(1)}，净位移 ${net.toStringAsFixed(1)}px）',
      );
    }
  }
}

void main() {
  testWidgets('竖屏触底放大：条目单调上移，终态精确贴底', (tester) async {
    final state = await _pump(
      tester,
      size: const Size(400, 800),
      initialZoom: kFolderZoomTierStandardList,
    );
    final controller = state.controller;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    final frames = await _transition(tester, state, kFolderZoomTierLargeGrid);
    _expectMonotonic(frames);

    expect(
      controller.offset,
      closeTo(controller.position.maxScrollExtent, 1.0),
      reason: '过渡结束后必须仍然贴底',
    );
    expect(frames.last.keys, contains(_kItemCount - 1));
  });

  testWidgets('横屏触底放大：条目单调上移，终态精确贴底', (tester) async {
    final state = await _pump(
      tester,
      size: const Size(1200, 800),
      initialZoom: kFolderZoomTierMinimalList,
    );
    final controller = state.controller;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    final frames = await _transition(tester, state, kFolderZoomTierLargeList);
    _expectMonotonic(frames);
    expect(
      controller.offset,
      closeTo(controller.position.maxScrollExtent, 1.0),
    );
  });

  testWidgets('触底缩小：条目单调下移，终态精确贴底', (tester) async {
    final state = await _pump(
      tester,
      size: const Size(1200, 800),
      initialZoom: kFolderZoomTierLargeGrid,
    );
    final controller = state.controller;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    final frames = await _transition(tester, state, kFolderZoomTierStandardList);
    _expectMonotonic(frames);
    expect(
      controller.offset,
      closeTo(controller.position.maxScrollExtent, 1.0),
    );
    expect(frames.last.keys, contains(_kItemCount - 1));
  });

  testWidgets('中段换档：条目单调平移，焦点内容仍然留在视口内', (tester) async {
    final state = await _pump(
      tester,
      size: const Size(1200, 800),
      initialZoom: kFolderZoomTierStandardList,
    );
    final controller = state.controller;
    controller.jumpTo(controller.position.maxScrollExtent / 2);
    await tester.pumpAndSettle();

    final before = _frame(tester);
    const focusY = 400.0;
    final anchor = before.keys.firstWhere(
      (i) => before[i]! <= focusY && before[i]! + 80 > focusY,
      orElse: () => before.keys.reduce(
        (a, b) => (before[a]! - focusY).abs() <= (before[b]! - focusY).abs()
            ? a
            : b,
      ),
    );

    final frames = await _transition(tester, state, kFolderZoomTierLargeGrid);
    _expectMonotonic(frames);
    expect(
      frames.last.keys,
      contains(anchor),
      reason: '焦点条目 $anchor 换档后应该还在视口里',
    );
  });

  testWidgets('过渡中再次换档（连点两档）不出现反向位移', (tester) async {
    final state = await _pump(
      tester,
      size: const Size(400, 800),
      initialZoom: kFolderZoomTierMinimalList,
    );
    final controller = state.controller;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    final frames = <_Frame>[];
    state.setZoom(kFolderZoomTierStandardList);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      frames.add(_frame(tester));
    }
    state.setZoom(kFolderZoomTierLargeGrid);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      frames.add(_frame(tester));
    }
    await tester.pumpAndSettle();
    frames.add(_frame(tester));

    _expectMonotonic(frames);
    expect(
      controller.offset,
      closeTo(controller.position.maxScrollExtent, 1.0),
    );
  });
}
