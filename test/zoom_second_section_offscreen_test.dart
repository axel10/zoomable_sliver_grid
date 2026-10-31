// 回归：一页两个列表 + 中间分段，屏幕内只看得到第一个列表和分段，第二个列表
// 整段还在屏幕下方 —— 此时缩小档位，第二个列表必须**整体跟随几何上移**，
// 不能把它的条目冻结成"原地淡入"（那会把条目钉在本段起始边上、再弹一次）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

const Object _dirs = 'dirs';
const Object _files = 'files';

class Harness extends StatefulWidget {
  const Harness({super.key});
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  final ScrollController controller = ScrollController();
  double zoom = kFolderZoomTierStandardList;
  FolderZoomLayoutMetrics? metrics;

  void setZoom(double v) => setState(() => zoom = v);

  Widget _section(
    FolderZoomLayoutMetrics metrics, {
    required Object section,
    required String prefix,
    required int count,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      sliver: SliverGrid(
        gridDelegate: SliverAnimatedZoomGridDelegate(
          metrics: metrics,
          section: section,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => ZoomItemScaffold(
            key: ValueKey('$prefix-$index'),
            metrics: metrics,
            section: section,
            titleText: '$prefix $index',
            subtitleText: 'S$index',
            infoText: '3:00',
          ),
          childCount: count,
        ),
      ),
    );
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
              builder: (context, metrics) {
                this.metrics = metrics;
                return CustomScrollView(
                  controller: controller,
                  slivers: [
                    const SliverToBoxAdapter(
                      child: SizedBox(key: ValueKey('header'), height: 96),
                    ),
                    _section(metrics,
                        section: _dirs, prefix: 'dir', count: 14),
                    const SliverToBoxAdapter(
                      child: SizedBox(key: ValueKey('intro'), height: 140),
                    ),
                    _section(metrics,
                        section: _files, prefix: 'file', count: 60),
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

double? _top(WidgetTester tester, String key) {
  final finder = find.byKey(ValueKey(key), skipOffstage: false);
  if (finder.evaluate().isEmpty) return null;
  return tester.getRect(finder.first).top;
}

void main() {
  testWidgets('第二个列表整段在屏幕外时缩小档位：条目整体上移，不被钉在分段边缘', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey<HarnessState>();
    await tester.pumpWidget(MaterialApp(home: Harness(key: key)));
    await tester.pumpAndSettle();
    final state = key.currentState!;

    // 滚到"分段完整可见、第二个列表首条刚好贴在折叠线下"的位置。
    double? start;
    double best = 1e9;
    for (var px = 0.0; px < state.controller.position.maxScrollExtent; px += 2) {
      state.controller.jumpTo(px);
      await tester.pump();
      final intro = _top(tester, 'intro');
      final file0 = _top(tester, 'file-0');
      if (intro == null || file0 == null) continue;
      if (intro + 140 > 800) continue;
      final score = (file0 - 810).abs();
      if (score < best) {
        best = score;
        start = px;
      }
    }
    expect(start, isNotNull, reason: '没找到"只见第一个列表 + 分段"的滚动位置');
    state.controller.jumpTo(start!);
    await tester.pumpAndSettle();

    expect(_top(tester, 'file-0')!, greaterThan(799.0),
        reason: '这个用例要求第二个列表首条在屏幕外');

    // 换档并逐帧采样：第二个列表的每一行都必须跟着几何单调上移。
    state.setZoom(kFolderZoomTierSmallGrid);
    final rows = <int>[0, 1, 8, 9];
    final trace = <int, List<double>>{for (final i in rows) i: <double>[]};
    for (var frame = 0; frame < 14; frame++) {
      await tester.pump(const Duration(milliseconds: 20));

      // 本段起始边还在视口顶端之下时，任何"原地淡入"的冻结都画不出来
      // （布局侧只能把它夹到本段起始边），所以这张表必须为空。
      final pinning = state.metrics?.pinningFor(_files);
      expect(pinning?.isEmpty ?? true, isTrue,
          reason: '第 $frame 帧给屏幕外的第二段冻结了 ${pinning?.firstPinnedIndex}'
              '..${pinning?.lastPinnedIndex}，这些条目会被钉在分段边缘再弹回去');

      final intro = _top(tester, 'intro');
      for (final i in rows) {
        final y = _top(tester, 'file-$i');
        if (y != null) trace[i]!.add(y);
        if (y != null && intro != null) {
          // 条目不可能跑到自己这一段起始边之上（分段底部之上）。
          expect(y, greaterThan(intro + 140 - 1.0),
              reason: '第 $frame 帧 file-$i 跑到了分段上面：y=$y intro=$intro');
        }
      }
    }
    await tester.pumpAndSettle();

    for (final i in rows) {
      final ys = trace[i]!;
      for (var k = 1; k < ys.length; k++) {
        expect(ys[k], lessThanOrEqualTo(ys[k - 1] + 2.0),
            reason: 'file-$i 在上移过程中出现回跳：$ys');
      }
      final settled = _top(tester, 'file-$i');
      if (settled != null && ys.isNotEmpty) {
        expect((ys.last - settled).abs(), lessThan(1.0),
            reason: 'file-$i 收尾时跳了 ${ys.last - settled}px：$ys -> $settled');
      }
    }
  });
}
