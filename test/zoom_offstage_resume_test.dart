import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

class _ParentRoute extends StatefulWidget {
  const _ParentRoute({required this.zoomNotifier});

  final ValueNotifier<double> zoomNotifier;

  @override
  State<_ParentRoute> createState() => _ParentRouteState();
}

class _ParentRouteState extends State<_ParentRoute> {
  final ScrollController _scrollController = ScrollController();
  FolderZoomLayoutMetrics? latestMetrics;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ValueListenableBuilder<double>(
        valueListenable: widget.zoomNotifier,
        builder: (context, zoom, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              return FolderZoomSliverBuilder(
                zoomScale: zoom,
                width: constraints.maxWidth,
                controller: _scrollController,
                builder: (context, metrics) {
                  latestMetrics = metrics;
                  return CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverGrid(
                        gridDelegate: SliverAnimatedZoomGridDelegate(
                          metrics: metrics,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => ZoomItemScaffold(
                            key: ValueKey('item-$index'),
                            metrics: metrics,
                            titleText: 'Item $index',
                          ),
                          childCount: 8,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

void main() {
  testWidgets(
    'background route settles to new zoomScale immediately on pop without replaying animation from old mode',
    (tester) async {
      final zoomNotifier = ValueNotifier<double>(kFolderZoomTierStandardList);
      addTearDown(zoomNotifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: _ParentRoute(zoomNotifier: zoomNotifier),
        ),
      );
      await tester.pumpAndSettle();

      final parentState =
          tester.state<_ParentRouteState>(find.byType(_ParentRoute));
      expect(parentState.latestMetrics?.contentIsGrid, isFalse);
      expect(parentState.latestMetrics?.gridMorph, 0.0);

      // Push an opaque child route so parent becomes offstage (TickerMode=false).
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('Child'))),
        ),
      );
      await tester.pumpAndSettle();

      // Change zoomScale while parent is in background.
      zoomNotifier.value = kFolderZoomTierLargeGrid;
      await tester.pump();

      // Pop child route and inspect the very first frame of the pop transition.
      navigator.pop();
      await tester.pump();

      final metricsOnPopFirstFrame = parentState.latestMetrics!;
      expect(metricsOnPopFirstFrame.targetZoomScale, kFolderZoomTierLargeGrid);
      expect(
        metricsOnPopFirstFrame.animatedZoomScale,
        closeTo(kFolderZoomTierLargeGrid, 1e-4),
      );
      expect(metricsOnPopFirstFrame.gridMorph, 1.0);
      expect(metricsOnPopFirstFrame.contentIsGrid, isTrue);

      await tester.pumpAndSettle();

      // Subsequent zoom change while active on screen still animates normally.
      zoomNotifier.value = kFolderZoomTierStandardList;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final metricsDuringActiveAnim = parentState.latestMetrics!;
      expect(metricsDuringActiveAnim.targetZoomScale, kFolderZoomTierStandardList);
      expect(metricsDuringActiveAnim.transitionProgress, lessThan(1.0));
      expect(metricsDuringActiveAnim.gridMorph, greaterThan(0.0));
      expect(metricsDuringActiveAnim.gridMorph, lessThan(1.0));

      await tester.pumpAndSettle();
      expect(parentState.latestMetrics?.gridMorph, 0.0);
      expect(parentState.latestMetrics?.contentIsGrid, isFalse);
    },
  );
}
