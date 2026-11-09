// 回归：插入位（虚线避让框）必须落在指针当前所在的槽位，不能横向跑偏。
//
// 曾把网格用 `(fy * columns + fx).round()` 线性化成一维：8 列时鼠标在第 0 行
// 第 1 列（local=(140,130)），`fy=0.756*8=6.05` 直接把插入位推到 7（最右列）。
// 网格必须按「行 + 列」二维分别取整。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

import 'package:example/reorder_demo_page.dart';

const _placeholderKey = ValueKey<String>('zoom-reorder-placeholder');

void main() {
  Future<void> pumpDemo(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReorderDemoPage()));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<ZoomReorderController> enterSelection(WidgetTester tester) async {
    await tester.longPress(find.text('Track 1 - Acoustic Echo'));
    await tester.pump(const Duration(milliseconds: 300));
    final element = tester.element(find.byType(ZoomReorderScope).first);
    return ZoomReorderScope.of(element);
  }

  testWidgets('网格态：多个格子的插入位与虚线框都贴合指针', (tester) async {
    await pumpDemo(tester);
    final controller = await enterSelection(tester);
    final geometry = controller.geometry!;
    expect(geometry.isGrid, isTrue);

    final origin = controller.resolveBox!()!.localToGlobal(Offset.zero);
    final start = tester.getCenter(find.byType(ZoomReorderHandle).first);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 300));

    // (row, col)：覆盖首行、不同列、以及第二行，确保二维取整不含跨列放大。
    const slots = <List<int>>[
      <int>[0, 1],
      <int>[0, 3],
      <int>[1, 3],
      <int>[0, 6],
    ];
    for (final slot in slots) {
      final row = slot[0];
      final col = slot[1];
      final target = origin +
          Offset(
            col * geometry.crossStride + geometry.cardWidth * 0.5,
            row * geometry.mainStride + geometry.cardHeight * 0.5,
          );
      await gesture.moveTo(target);
      // 先让 notifyListeners 的 rebuild 把新目标喂给 AnimatedPositioned，
      // 再单独推进一帧跑完 220ms 位移动画（同一帧里动画还没开始 tick）。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        controller.insertIndex,
        row * geometry.columns + col,
        reason: '指针落在 ($row,$col) 时插入位不应被算到别的列',
      );
      final rect = tester.getRect(find.byKey(_placeholderKey));
      expect(
        rect.contains(target),
        isTrue,
        reason: '虚线避让框应罩住指针 $target，实际 $rect',
      );
    }

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.isDragging, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('列表态：插入位仍按行计算，避让框横跨整行', (tester) async {
    await pumpDemo(tester);
    await tester.tap(find.text('列表档'));
    await tester.pump(const Duration(milliseconds: 600));

    final controller = await enterSelection(tester);
    final geometry = controller.geometry!;
    expect(geometry.isGrid, isFalse);

    final start = tester.getCenter(find.byType(ZoomReorderHandle).first);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(10, 120));
    await tester.pump(const Duration(milliseconds: 300));

    final box = controller.resolveBox!()!;
    final local = box.globalToLocal(controller.pointer.value);
    expect(
      controller.insertIndex,
      (local.dy / geometry.listStride).round(),
    );
    final rect = tester.getRect(find.byKey(_placeholderKey));
    expect(rect.left, lessThanOrEqualTo(controller.pointer.value.dx));
    expect(rect.right, greaterThanOrEqualTo(controller.pointer.value.dx));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
