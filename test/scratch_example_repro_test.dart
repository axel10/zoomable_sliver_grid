// 临时复现脚本：完全照 example/lib/main.dart 的结构搭（Scaffold + AppBar +
// LayoutBuilder + ZoomGestureLayer + FolderZoomSliverBuilder + CustomScrollView，
// 且**不传 controller**），用来验证 `_scrollPosition()` 是否挑错了 viewport。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

class Harness extends StatefulWidget {
  const Harness({super.key});

  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  double zoom = kFolderZoomTierStandardList;

  void setZoom(double value) => setState(() => zoom = value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('demo')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return ZoomGestureLayer(
            zoomScale: zoom,
            onZoomScaleChanged: (value) => setState(() => zoom = value),
            child: FolderZoomSliverBuilder(
              zoomScale: zoom,
              width: constraints.maxWidth,
              builder: (context, metrics) {
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: folderContentHorizontalPadding(
                          isPortrait: metrics.isPortrait,
                          gridMorph: metrics.gridMorph,
                        ),
                        vertical: 16.0,
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
            ),
          );
        },
      ),
    );
  }
}

void main() {
  testWidgets('复现：不传 controller + Scaffold 结构下的换档', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final key = GlobalKey<HarnessState>();
    await tester.pumpWidget(MaterialApp(home: Harness(key: key)));
    await tester.pumpAndSettle();

    debugPrint('=== 滚动到列表中部 ===');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    debugPrint('=== 换档 0.333 -> 0.500 ===');
    key.currentState!.setZoom(kFolderZoomTierCompactList);
    await tester.pumpAndSettle();

    debugPrint('=== 换档 0.500 -> 0.667 ===');
    key.currentState!.setZoom(kFolderZoomTierSmallGrid);
    await tester.pumpAndSettle();
  });
}
