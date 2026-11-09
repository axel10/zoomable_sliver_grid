// 拖拽排序 demo 的冒烟测试：确认网格/列表两档都能渲染，
// 长按进入多选后出现手柄，拖拽过程中合集浮层可见，松手后不残留状态。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

import 'package:example/reorder_demo_page.dart';

void main() {
  Future<void> pumpDemo(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReorderDemoPage()));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('网格档首帧渲染，切到列表档不崩', (tester) async {
    await pumpDemo(tester);
    expect(find.text('拖拽排序 demo'), findsOneWidget);
    expect(find.text('Track 1 - Acoustic Echo'), findsOneWidget);

    await tester.tap(find.text('列表档'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Track 1 - Acoustic Echo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按进入多选后出现手柄，拖拽出现合集浮层', (tester) async {
    await pumpDemo(tester);
    expect(find.byType(ZoomReorderHandle), findsNothing);

    await tester.longPress(find.text('Track 1 - Acoustic Echo'));
    await tester.pump(const Duration(milliseconds: 300));
    final handles = find.byType(ZoomReorderHandle);
    expect(handles, findsWidgets);

    final start = tester.getCenter(handles.first);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ZoomReorderPreview), findsOneWidget);

    await gesture.moveTo(start + const Offset(0, 260));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    final element = tester.element(find.byType(ZoomReorderScope).first);
    final controller = ZoomReorderScope.of(element);
    expect(controller.isDragging, isFalse);
    expect(controller.reorderActive.value, isFalse);
    expect(tester.takeException(), isNull);
    expect(find.byType(ZoomReorderPreview), findsNothing);
  });
}
