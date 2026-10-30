import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 需求回归：换档时**只有两侧档位都可见**的条目才做位移动画，
/// 只在一侧可见的条目必须**原地淡入 / 淡出**（位置不动）。
///
/// 这条需求一度被整块删掉：`3cc4109` 为修"触底换档从下往上弹一下"，把
/// `resolveItemTransition` 改成恒返回 `isShared: true`，结果所有条目都走加权
/// 位移，单侧条目从很远的地方飞进 / 飞出。弹跳的真实成因是**可见性逐帧重算会
/// 反复翻转**，而不是分类本身错了 —— 现在分类在过渡开始时冻结一次
/// （`FolderZoomItemPinning`），两个问题一起解决。
///
/// 本测试盯住三件事：
/// 1. 过渡中确实存在单侧可见的条目被划到 `fadeIn` / `fadeOut`；
/// 2. 这些条目整段过渡里屏幕位置**不动**（原地），且不透明度在变；
/// 3. 两侧都可见的条目**仍然在位移**（没有把全体都钉死）。

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
            return FolderZoomSliverBuilder(
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

/// 切档并逐帧采样。
Future<List<_Frame>> _transition(
  WidgetTester tester,
  _HarnessState state,
  double targetZoom, {
  int frames = 12,
}) async {
  state.setZoom(targetZoom);
  await tester.pump();
  final samples = <_Frame>[
    (tops: _tops(tester), metrics: state.metrics),
  ];
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    samples.add((tops: _tops(tester), metrics: state.metrics));
  }
  return samples;
}

/// 断言 [kind] 类条目的屏幕位置整段过渡不变、且不透明度确实在向 0 或 1 走。
void _expectPinnedInPlace(
  List<_Frame> samples,
  FolderZoomItemPin kind, {
  required int minCount,
}) {
  final pinning = samples.first.metrics.itemPinning;
  expect(pinning, isNotNull, reason: '过渡开始就必须冻结出单侧条目处置表');

  final pinned = <int>[
    for (var i = 0; i < _kItemCount; i++)
      if (pinning!.pinOf(i) == kind) i,
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
      opacities.add(
        sample.metrics.resolveItemTransition(index).opacity,
      );
    }
    if (tops.length < 3) continue;

    final min = tops.reduce((a, b) => a < b ? a : b);
    final max = tops.reduce((a, b) => a > b ? a : b);
    expect(
      max - min,
      lessThan(1.5),
      reason: '条目 $index（${kind.name}）应该原地不动，'
          '却在 $min ~ $max 之间移动了 ${(max - min).toStringAsFixed(1)}px',
    );

    final first = opacities.first;
    final last = opacities.last;
    if (kind == FolderZoomItemPin.fadeOut) {
      expect(last, lessThan(first), reason: '条目 $index 应该在淡出');
    } else {
      expect(last, greaterThan(first), reason: '条目 $index 应该在淡入');
    }
  }
}

/// 断言还有条目在真正位移（否则等于把所有条目都钉死了）。
void _expectSharedItemsStillMove(List<_Frame> samples) {
  var moved = 0;
  final first = samples.first;
  final last = samples.last;
  for (final index in first.tops.keys) {
    final from = first.tops[index];
    final to = last.tops[index];
    if (from == null || to == null) continue;
    if (first.metrics.resolveItemTransition(index).isShared &&
        (to - from).abs() > 8.0) {
      moved++;
    }
  }
  expect(moved, greaterThan(0), reason: '两侧都可见的条目必须继续做位移动画');
}

/// 断言还条目真的被渲染成半透明（`ZoomItemScaffold` 的 `isFadeScale` 分支生效），
/// 而不是只有 metrics 算出了 opacity。
void _expectRenderedOpacity(WidgetTester tester, _Frame frame) {
  final pinning = frame.metrics.itemPinning;
  expect(pinning, isNotNull);
  final int index = pinning!.firstPinnedIndex!;
  expect(pinning.firstPinnedIndex, isNotNull, reason: '这一帧应该有锁定条目');

  final finder = find.byKey(ValueKey('item-$index'), skipOffstage: false);
  expect(finder, findsOneWidget);
  final values = find
      .descendant(of: finder, matching: find.byType(Opacity))
      .evaluate()
      .map((element) => (element.widget as Opacity).opacity)
      .toList();
  final double expected =
      frame.metrics.resolveItemTransition(index).opacity;
  expect(expected, greaterThan(0.0));
  expect(expected, lessThan(1.0));
  expect(
    values.any((value) => (value - expected).abs() < 0.001),
    isTrue,
    reason: 'item $index 的渲染树里应有一个不透明度为 '
        '${expected.toStringAsFixed(3)} 的 Opacity，实际 ${values.map((v) => v.toStringAsFixed(3)).toList()}',
  );
}

void main() {
  // 400×800 竖屏下 LargeGrid 是 2 列大卡（每行两张），一屏只放得下 6 条；
  // StandardList 一屏 10 条。所以列表 → 网格是"变稀"，多出来的 4 条要淡出。
  testWidgets('列表 → 网格：只在列表可见的条目原地淡出、不位移', (tester) async {
    final state = await _pump(
      tester,
      size: const Size(400, 800),
      initialZoom: kFolderZoomTierStandardList,
    );

    final samples = await _transition(
      tester,
      state,
      kFolderZoomTierLargeGrid,
    );

    _expectPinnedInPlace(
      samples,
      FolderZoomItemPin.fadeOut,
      minCount: 3,
    );
    // 控件树停在最后一帧，所以拿最后一帧的 metrics 对照。
    _expectRenderedOpacity(tester, samples.last);
    _expectSharedItemsStillMove(samples);
  });

  testWidgets('网格 → 列表：只在列表可见的条目原地淡入、不位移', (tester) async {
    final state = await _pump(
      tester,
      size: const Size(400, 800),
      initialZoom: kFolderZoomTierLargeGrid,
    );

    final samples = await _transition(
      tester,
      state,
      kFolderZoomTierStandardList,
    );

    _expectPinnedInPlace(
      samples,
      FolderZoomItemPin.fadeIn,
      minCount: 3,
    );
    _expectSharedItemsStillMove(samples);
  });

  testWidgets('连点两档：重新冻结分类时锁定条目也不跳一下', (tester) async {
    final state = await _pump(
      tester,
      size: const Size(1200, 800),
      initialZoom: kFolderZoomTierMinimalList,
    );
    final controller = state.controller;
    controller.jumpTo(controller.position.maxScrollExtent / 2);
    await tester.pumpAndSettle();

    final samples = <_Frame>[];
    state.setZoom(kFolderZoomTierStandardList);
    await tester.pump();
    samples.add((tops: _tops(tester), metrics: state.metrics));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      samples.add((tops: _tops(tester), metrics: state.metrics));
    }
    // 第一段过渡还没跑完就再换一档：会重新冻结一张处置表，锁定值取的是
    // 上一帧**真实画出来的**位置，所以不允许出现位置跳变。
    state.setZoom(kFolderZoomTierLargeGrid);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      samples.add((tops: _tops(tester), metrics: state.metrics));
    }

    for (var f = 1; f < samples.length; f++) {
      final previous = samples[f - 1];
      final current = samples[f];
      final pinning = current.metrics.itemPinning;
      if (pinning == null) continue;
      for (final entry in current.tops.entries) {
        if (pinning.pinOf(entry.key) == FolderZoomItemPin.shared) continue;
        final before = previous.tops[entry.key];
        if (before == null) continue;
        expect(
          (entry.value - before).abs(),
          lessThan(4.0),
          reason: '锁定条目 ${entry.key} 在第 $f 帧跳了 '
              '${(entry.value - before).toStringAsFixed(1)}px',
        );
      }
    }
    await tester.pumpAndSettle();
  });
}
