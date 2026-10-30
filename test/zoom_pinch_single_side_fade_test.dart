import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 回归：**双指捏合换档必须和点击档位换档完全一致** ——
/// 只有两侧档位都可见的条目做位移动画，只在一侧可见的条目锁在原地淡入 / 淡出。
///
/// 早期 `build()` 的捏合分支没有把 `itemPinning` 传进 [FolderZoomLayoutMetrics]，
/// 整段捏合都退化成"所有条目按两端几何加权位移"：屏幕上就是「双指一捏，
/// 整屏条目一起往上 / 往下漂」。点击档位走的是 `_applyTargets` 那条路，里面有
/// `buildPinning()`，所以同一个换档点击时是对的、捏合时是错的。
///
/// 本测试用真实双指手势驱动 [ZoomGestureLayer]，盯住三件事：
/// 1. 捏合过程中确实冻结出了单侧条目处置表；
/// 2. 这些条目整段手势里屏幕位置**不动**，不透明度在变；
/// 3. 两侧都可见的条目仍然在位移。

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
  late FolderZoomLayoutMetrics metrics;

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
              builder: (context, m) {
                metrics = m;
                return CustomScrollView(
                  controller: controller,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: folderContentHorizontalPadding(
                          isPortrait: m.isPortrait,
                          gridMorph: m.gridMorph,
                        ),
                        vertical: 16,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: SliverAnimatedZoomGridDelegate(metrics: m),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => ZoomItemScaffold(
                            key: ValueKey('item-$index'),
                            metrics: m,
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
            return ZoomGestureLayer(
              zoomScale: zoom,
              onZoomScaleChanged: setZoom,
              enableHaptics: false,
              child: content,
            );
          },
        ),
      ),
    );
  }
}

typedef _Frame = ({Map<int, double> tops, FolderZoomLayoutMetrics metrics});

Map<int, double> _tops(WidgetTester tester) {
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
  required double initialZoom,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(_Harness(key: key, initialZoom: initialZoom));
  await tester.pumpAndSettle();
  return key.currentState!;
}

/// 双指捏合：`zoomIn` 时两根手指分开（档位变大），否则靠拢（档位变小）。
///
/// 焦点（双指中点）固定在 (200, 350)，手指位移是纯径向的，所以锚点不动，
/// 断言里出现的位移都只能来自条目自身的布局。
Future<List<_Frame>> _pinch(
  WidgetTester tester,
  _HarnessState state, {
  required bool zoomIn,
  int steps = 6,
}) async {
  final g1 = await tester.startGesture(const Offset(150, 300), pointer: 11);
  final g2 = await tester.startGesture(const Offset(250, 400), pointer: 12);
  await tester.pump(const Duration(milliseconds: 16));

  final samples = <_Frame>[];
  for (var step = 1; step <= steps; step++) {
    final double d = (zoomIn ? 1 : -1) * step * 8.0;
    await g1.moveTo(Offset(150 - d, 300 - d));
    await g2.moveTo(Offset(250 + d, 400 + d));
    await tester.pump(const Duration(milliseconds: 16));
    samples.add((tops: _tops(tester), metrics: state.metrics));
  }
  addTearDown(() async {
    await g1.up();
    await g2.up();
  });
  return samples;
}

/// 取第一帧"已经冻结出处置表"的样本作为参照。
_Frame _firstFrozen(List<_Frame> samples) {
  for (final sample in samples) {
    final pinning = sample.metrics.itemPinning;
    if (pinning != null && !pinning.isEmpty) return sample;
  }
  fail('整段捏合都没有冻结出单侧条目处置表：捏合路径又退回成"全体加权位移"了');
}

void _expectPinnedInPlace(
  List<_Frame> samples,
  FolderZoomItemPin kind, {
  required int minCount,
}) {
  final frozen = _firstFrozen(samples);
  final pinning = frozen.metrics.itemPinning!;
  final pinned = <int>[
    for (var i = 0; i < _kItemCount; i++)
      if (pinning.pinOf(i) == kind) i,
  ];
  expect(
    pinned.length,
    greaterThanOrEqualTo(minCount),
    reason: '${kind.name} 条目应有至少 $minCount 条，实际 ${pinned.length}',
  );

  for (final index in pinned) {
    final tops = <double>[];
    final opacities = <double>[];
    for (final sample in samples) {
      final top = sample.tops[index];
      if (top == null) continue;
      tops.add(top);
      opacities.add(sample.metrics.resolveItemTransition(index).opacity);
    }
    if (tops.length < 3) continue;

    final double min = tops.reduce((a, b) => a < b ? a : b);
    final double max = tops.reduce((a, b) => a > b ? a : b);
    expect(
      max - min,
      lessThan(1.5),
      reason: '条目 $index（${kind.name}）应该原地不动，'
          '却在 $min ~ $max 之间移动了 ${(max - min).toStringAsFixed(1)}px',
    );

    final double first = opacities.first;
    final double last = opacities.last;
    if (kind == FolderZoomItemPin.fadeOut) {
      expect(last, lessThan(first), reason: '条目 $index 应该在淡出');
    } else {
      expect(last, greaterThan(first), reason: '条目 $index 应该在淡入');
    }
  }
}

void _expectSharedItemsStillMove(List<_Frame> samples) {
  final frozen = _firstFrozen(samples);
  final first = frozen.tops;
  final last = samples.last.tops;
  var moved = 0;
  for (final index in first.keys) {
    final from = first[index];
    final to = last[index];
    if (from == null || to == null) continue;
    if (frozen.metrics.resolveItemTransition(index).isShared &&
        (to - from).abs() > 8.0) {
      moved++;
    }
  }
  expect(moved, greaterThan(0), reason: '两侧都可见的条目必须继续位移');
}

void main() {
  // 400×800 竖屏：StandardList 一屏 10 条（步距 80），LargeList 一屏 8 条
  // （步距 104）。列表 → 列表放大时多出来的条目只在起始档位可见，要原地淡出。
  testWidgets('捏合放大：只在起始档位可见的条目原地淡出、不位移', (tester) async {
    final state = await _pump(tester, initialZoom: kFolderZoomTierStandardList);
    expect(state.controller.offset, 0.0, reason: '本用例固定在顶部，避免锚点混入变量');

    final samples = await _pinch(tester, state, zoomIn: true);
    _expectPinnedInPlace(samples, FolderZoomItemPin.fadeOut, minCount: 2);
    _expectSharedItemsStillMove(samples);
  });

  testWidgets('捏合缩小：只在目标档位可见的条目原地淡入、不位移', (tester) async {
    final state = await _pump(tester, initialZoom: kFolderZoomTierLargeList);
    expect(state.controller.offset, 0.0);

    final samples = await _pinch(tester, state, zoomIn: false);
    _expectPinnedInPlace(samples, FolderZoomItemPin.fadeIn, minCount: 2);
    _expectSharedItemsStillMove(samples);
  });
}
