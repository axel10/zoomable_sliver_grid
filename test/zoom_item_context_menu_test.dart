import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

void main() {
  testWidgets('ZoomItemScaffold triggers onContextMenu only once on long press with correct position',
      (tester) async {
    final positions = <Offset>[];
    var longPressCount = 0;

    final metrics = FolderZoomLayoutMetrics(
      targetZoomScale: 1.0,
      animatedZoomScale: 1.0,
      gridMorph: 1.0,
      compactMorph: 0.0,
      animatedGridCols: 4.0,
      animatedGridTextHeight: 60.0,
      animatedListExtent: 56.0,
      targetCardWidth: 150.0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 150.0,
              height: 210.0,
              child: ZoomItemScaffold(
                metrics: metrics,
                titleText: 'Server Item',
                onContextMenu: (position) {
                  positions.add(position);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final itemFinder = find.text('Server Item');
    expect(itemFinder, findsOneWidget);

    final itemCenter = tester.getCenter(itemFinder);

    // 触发长按手势
    await tester.longPress(itemFinder);
    await tester.pumpAndSettle();

    // 校验：只触发了一次 onContextMenu，且坐标不为 Offset.zero
    expect(positions.length, equals(1));
    expect(positions.first, isNot(equals(Offset.zero)));
    expect(positions.first, equals(itemCenter));

    // 接下来测试：如果显式提供了 onLongPress，onLongPress 仍正常响应
    positions.clear();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 150.0,
              height: 210.0,
              child: ZoomItemScaffold(
                metrics: metrics,
                titleText: 'Server Item 2',
                onLongPress: () {
                  longPressCount++;
                },
                onContextMenu: (position) {
                  positions.add(position);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final item2Finder = find.text('Server Item 2');
    await tester.longPress(item2Finder);
    await tester.pumpAndSettle();

    expect(positions.length, equals(1));
    expect(longPressCount, equals(1));
  });
}
