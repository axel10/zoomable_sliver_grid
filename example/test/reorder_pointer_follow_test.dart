// 回归：拖拽过程中合集浮层必须持续跟随指针，插入位也要随之变化。
//
// 曾有两个叠加缺陷：
// 1) 起拖后被拖条目 hidden，手柄按 `enabled: !hidden` 换成普通 Container，
//    而 pointer 的命中路径是 down 时缓存的，换掉包装层后后续 move 全丢；
// 2) 手柄只靠 GestureDetector 的 pan 更新位置，一旦被 CustomScrollView 抢赢
//    手势竞技场，onPanUpdate 停发且 onPanCancel 未必送达，浮层就冻在原地。
// 修法：手势层常驻 + Listener 直接吃 pointer + 占位 recognizer 立即 accept。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

import 'package:example/reorder_demo_page.dart';

void main() {
  Future<void> pumpDemo(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReorderDemoPage()));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('拖拽中合集浮层与插入位跟随指针', (tester) async {
    await pumpDemo(tester);
    await tester.longPress(find.text('Track 1 - Acoustic Echo'));
    await tester.pump(const Duration(milliseconds: 300));

    final start = tester.getCenter(find.byType(ZoomReorderHandle).first);
    final gesture = await tester.startGesture(start);
    final firstTarget = start + const Offset(20, 100);
    await gesture.moveTo(firstTarget);
    await tester.pump(const Duration(milliseconds: 100));

    final element = tester.element(find.byType(ZoomReorderScope).first);
    final controller = ZoomReorderScope.of(element);
    final preview = find.byType(ZoomReorderPreview);
    expect(controller.isDragging, isTrue);
    expect(preview, findsOneWidget);
    final firstPointer = controller.pointer.value;
    final firstRect = tester.getRect(preview);
    final firstInsert = controller.insertIndex;

    const shift = Offset(160, 140);
    await gesture.moveTo(firstTarget + shift);
    await tester.pump(const Duration(milliseconds: 100));

    expect(controller.pointer.value, firstPointer + shift);
    expect(tester.getRect(preview).topLeft, firstRect.topLeft + shift);
    expect(controller.insertIndex, isNot(firstInsert));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.isDragging, isFalse);
    expect(controller.reorderActive.value, isFalse);
    expect(find.byType(ZoomReorderPreview), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('多选拖拽时合集浮层带整组条数', (tester) async {
    await pumpDemo(tester);
    await tester.longPress(find.text('Track 1 - Acoustic Echo'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.longPress(find.text('Track 2 - Acoustic Echo'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('已选 2 条'), findsOneWidget);

    final start = tester.getCenter(find.byType(ZoomReorderHandle).first);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(10, 100));
    await tester.pump(const Duration(milliseconds: 100));

    final preview = tester.widget<ZoomReorderPreview>(
      find.byType(ZoomReorderPreview),
    );
    expect(preview.count, 2);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
