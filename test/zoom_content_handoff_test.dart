// 回归测试：网格 ↔ 列表的内容排版只能在"完全看不见"的那一帧换掉。
//
// 背景：两套内容排版结构不同（封面在上 + 标题在下方 vs 封面在左 + 标题垂直居中），
// 无法逐属性插值，只能整份换。实测交接帧标题会瞬移 30~40px；如果那时还有
// 不透明度（旧实现 0.74~0.90），屏幕上就是"条目内容在动画中途跳一下"。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

const int kCount = 12;

class _Page extends StatefulWidget {
  const _Page({super.key, required this.initialZoom});
  final double initialZoom;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  late double zoom = widget.initialZoom;
  FolderZoomLayoutMetrics? metrics;
  final ScrollController controller = ScrollController();

  void setZoom(double value) => setState(() => zoom = value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('handoff')),
      body: LayoutBuilder(
        builder: (context, c) {
          return ZoomGestureLayer(
            zoomScale: zoom,
            onZoomScaleChanged: (v) => setState(() => zoom = v),
            enableHaptics: false,
            child: FolderZoomSliverBuilder(
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
                        vertical: 8.0,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: SliverAnimatedZoomGridDelegate(metrics: m),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => ZoomItemScaffold(
                            key: ValueKey('item-$index'),
                            metrics: m,
                            titleText: 'T$index',
                            subtitleText: 'Sub',
                            infoText: '3:20',
                          ),
                          childCount: kCount,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// 跑一遍换档，返回逐帧的 `(contentIsGrid, contentReveal, titleTop)`。
Future<List<({bool isGrid, double reveal, double? titleTop})>> _trace(
  WidgetTester tester,
  double from,
  double to,
) async {
  final key = GlobalKey<_PageState>();
  await tester.pumpWidget(MaterialApp(home: _Page(key: key, initialZoom: from)));
  await tester.pumpAndSettle();

  final start = key.currentState!.metrics!;
  expect(start.contentReveal, 1.0, reason: '稳态内容必须完全不透明');

  key.currentState!.setZoom(to);

  final out = <({bool isGrid, double reveal, double? titleTop})>[];
  for (var f = 0; f < 60; f++) {
    await tester.pump(const Duration(milliseconds: 16));
    final m = key.currentState!.metrics;
    if (m == null) continue;
    final title = find.text('T2', skipOffstage: false);
    out.add((
      isGrid: m.contentIsGrid ?? (m.gridMorph >= 0.5),
      reveal: m.contentReveal,
      titleTop: title.evaluate().isEmpty ? null : tester.getRect(title.first).top,
    ));
    if ((m.transitionProgress - 1).abs() < 1e-6) break;
  }
  await tester.pumpAndSettle();
  return out;
}

void main() {
  testWidgets('网格 -> 列表：换布局那一帧内容不可见', (tester) async {
    tester.view.physicalSize = const Size(394, 862);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final trace = await _trace(
      tester,
      kFolderZoomTierSmallGrid,
      kFolderZoomTierLargeList,
    );
    expect(trace.length, greaterThan(4));

    var flips = 0;
    for (var i = 1; i < trace.length; i++) {
      if (trace[i].isGrid == trace[i - 1].isGrid) continue;
      flips++;
      expect(
        trace[i].reveal,
        lessThan(0.02),
        reason: '第 $i 帧换了内容布局，此时不透明度 ${trace[i].reveal} '
            '会让标题从 ${trace[i - 1].titleTop} 瞬移到 ${trace[i].titleTop}',
      );
      // 交帧前后各一帧也必须已经压得很暗，不能"亮着换"。
      expect(trace[i - 1].reveal, lessThan(0.4));
    }
    expect(flips, 1, reason: '一次换档只应发生一次内容交接');
    expect(trace.last.isGrid, isFalse);
    expect(trace.last.reveal, 1.0);
  });

  testWidgets('列表 -> 网格：换布局那一帧内容不可见', (tester) async {
    tester.view.physicalSize = const Size(394, 862);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final trace = await _trace(
      tester,
      kFolderZoomTierLargeList,
      kFolderZoomTierSmallGrid,
    );
    expect(trace.length, greaterThan(4));

    var flips = 0;
    for (var i = 1; i < trace.length; i++) {
      if (trace[i].isGrid == trace[i - 1].isGrid) continue;
      flips++;
      expect(trace[i].reveal, lessThan(0.02));
      expect(trace[i - 1].reveal, lessThan(0.4));
    }
    expect(flips, 1);
    expect(trace.last.isGrid, isTrue);
    expect(trace.last.reveal, 1.0);
  });
}
