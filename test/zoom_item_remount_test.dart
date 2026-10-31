import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 需求回归：换档过渡开始 / 结束时，已经挂载的条目**不得被重建**。
///
/// `ZoomItemScaffold` 曾经把三层包装（`Opacity` / `Transform` / `ZoomItemEffectiveMetrics`）
/// 按 `isFadeScale` 条件增删。单侧可见条目在过渡**收尾**那一帧正好从
/// `Opacity > Transform > ZoomItemEffectiveMetrics > HoverableCard` 塌缩成
/// `HoverableCard`，`LayoutBuilder` 之下的根 Widget 类型一变，Flutter 就只能把整条
/// 子树 deactivate 重建 —— 条目里的 `SongThumbnail` 丢掉 State（`_isGenerating`
/// 回到 true），表现为「淡入结束之后，落定为默认图标的条目闪一下 / 重新解析一遍」。
/// 日志里同一批路径一次换档解析两遍，就是这个重建。
///
/// 本测试用一个只在 `initState` 计数的探针盯住这件事：过渡收尾之后，过渡期间
/// 已经挂载的条目，其 `initState` 次数不允许再增加。
const int _kItemCount = 80;

/// `initState` 计数探针：计数增加 = 这一条被重建过。
class _Probe extends StatefulWidget {
  const _Probe({required this.index, required this.onInit});

  final int index;
  final void Function(int index) onInit;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return Text('P${widget.index}');
  }
}

class _Harness extends StatefulWidget {
  const _Harness({super.key, required this.initialZoom, required this.initCounts});

  final double initialZoom;
  final Map<int, int> initCounts;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final ScrollController controller = ScrollController();
  late double zoom = widget.initialZoom;
  late FolderZoomLayoutMetrics metrics;

  void setZoom(double value) => setState(() => zoom = value);

  void _countInit(int index) {
    widget.initCounts[index] = (widget.initCounts[index] ?? 0) + 1;
  }

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
                            textColumn: _Probe(index: index, onInit: _countInit),
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

Future<_HarnessState> _pump(
  WidgetTester tester,
  Map<int, int> initCounts, {
  required Size size,
  required double initialZoom,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(
    _Harness(key: key, initialZoom: initialZoom, initCounts: initCounts),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

void main() {
  testWidgets('换档收尾：过渡期间已挂载的条目不被重建', (tester) async {
    final initCounts = <int, int>{};

    // 400×800 竖屏下 LargeGrid 只放得下 6 条，StandardList 一屏 10 条，
    // 所以「网格 → 列表」是变密，多出来的条目会被划成 fadeIn 单侧条目。
    final state = await _pump(
      tester,
      initCounts,
      size: const Size(400, 800),
      initialZoom: kFolderZoomTierLargeGrid,
    );

    state.setZoom(kFolderZoomTierStandardList);
    await tester.pump();

    // 逐帧跑到 14×16ms ≈ 224ms，还没到 260ms 的过渡终点。
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      state.metrics.itemPinning,
      isNotNull,
      reason: '这一帧应仍处于过渡中（冻结表还在）',
    );
    final duringTransition = Map<int, int>.of(initCounts);
    expect(duringTransition, isNotEmpty);

    // 越过过渡终点（260ms）再多跑几帧，让收尾那一帧的重建机会都发生。
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(
      state.metrics.itemPinning,
      isNull,
      reason: '过渡应已结束（冻结表失效）',
    );

    for (final entry in duringTransition.entries) {
      expect(
        initCounts[entry.key],
        entry.value,
        reason: '条目 ${entry.key} 在过渡收尾时被重建了'
            '（initState 从 ${entry.value} 变成 ${initCounts[entry.key]}）；'
            '说明 ZoomItemScaffold 的包装层还在按条件增删',
      );
    }
  });

  testWidgets('换档起步：两侧都可见的条目不被重建', (tester) async {
    final initCounts = <int, int>{};

    final state = await _pump(
      tester,
      initCounts,
      size: const Size(400, 800),
      initialZoom: kFolderZoomTierStandardList,
    );
    final before = Map<int, int>.of(initCounts);

    state.setZoom(kFolderZoomTierCompactList);
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    for (final entry in before.entries) {
      expect(
        initCounts[entry.key],
        entry.value,
        reason: '条目 ${entry.key} 在过渡起步时被重建了',
      );
    }
  });
}
