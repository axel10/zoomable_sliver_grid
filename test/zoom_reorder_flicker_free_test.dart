import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

void main() {
  final metrics = FolderZoomLayoutMetrics(
    targetZoomScale: 1.0,
    animatedZoomScale: 1.0,
    gridMorph: 1.0,
    compactMorph: 0.0,
    animatedGridCols: 3.0,
    animatedGridTextHeight: 40.0,
    animatedListExtent: 60.0,
    targetCardWidth: 100.0,
  );

  testWidgets('传 itemKeyBuilder 时，拖拽松手后被交换位置的条目不应闪烁（透明度保持1.0）', (tester) async {
    var items = <int>[1, 2, 3];
    late StateSetter outerSetState;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              outerSetState = setState;
              return CustomScrollView(
                slivers: [
                  ZoomReorderableSliverGrid(
                    metrics: metrics,
                    width: 360,
                    itemCount: items.length,
                    itemKeyBuilder: (index) => ValueKey<int>(items[index]),
                    showHandles: true,
                    onReorder: (dragged, at) {
                      outerSetState(() {
                        items = ZoomReorderController.applyReorder(items, dragged, at);
                      });
                    },
                    itemBuilder: (context, index) => Text('Item ${items[index]}'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final handles = find.byType(ZoomReorderHandle);
    final gesture = await tester.startGesture(tester.getCenter(handles.first));
    await gesture.moveTo(tester.getCenter(handles.at(1)) + const Offset(0, 10));
    await tester.pump(const Duration(milliseconds: 300));

    await gesture.up();
    await tester.pump(); // 首帧

    final item2Text = find.text('Item 2');
    final opacities = tester.widgetList<Opacity>(
      find.ancestor(of: item2Text, matching: find.byType(Opacity)),
    );
    expect(opacities, isNotEmpty);
    for (final op in opacities) {
      expect(op.opacity, 1.0, reason: '松手后 Item 2 的透明度应当立即保持为 1.0');
    }
  });

  testWidgets('不传 itemKeyBuilder 时，松手后透明度也不会降为 0.0', (tester) async {
    var items = <String>['A', 'B', 'C'];
    late StateSetter outerSetState;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              outerSetState = setState;
              return CustomScrollView(
                slivers: [
                  ZoomReorderableSliverGrid(
                    metrics: metrics,
                    width: 360,
                    itemCount: items.length,
                    showHandles: true,
                    onReorder: (dragged, at) {
                      outerSetState(() {
                        items = ZoomReorderController.applyReorder(items, dragged, at);
                      });
                    },
                    itemBuilder: (context, index) => Text('Item ${items[index]}'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final handles = find.byType(ZoomReorderHandle);
    final gesture = await tester.startGesture(tester.getCenter(handles.first));
    await gesture.moveTo(tester.getCenter(handles.at(1)) + const Offset(0, 10));
    await tester.pump(const Duration(milliseconds: 300));

    await gesture.up();
    await tester.pump(); // 首帧

    final itemBText = find.text('Item B');
    final opacities = tester.widgetList<Opacity>(
      find.ancestor(of: itemBText, matching: find.byType(Opacity)),
    );
    expect(opacities, isNotEmpty);
    for (final op in opacities) {
      expect(op.opacity, 1.0);
    }
  });
}
