import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

void main() {
  group('applyReorder', () {
    test('单条：从 0 插到第 2 位', () {
      expect(
        ZoomReorderController.applyReorder<int>(<int>[0, 1, 2, 3], <int>{0}, 2),
        <int>[1, 2, 0, 3],
      );
    });

    test('多条：被拖集合保持原有相对顺序', () {
      expect(
        ZoomReorderController.applyReorder<int>(
          <int>[0, 1, 2, 3, 4, 5],
          <int>{1, 3},
          2,
        ),
        <int>[0, 2, 1, 3, 4, 5],
      );
    });

    test('空集合与越界插入位都不炸', () {
      final items = <int>[0, 1, 2];
      expect(
        ZoomReorderController.applyReorder<int>(items, <int>{}, 99),
        items,
      );
      expect(
        ZoomReorderController.applyReorder<int>(items, <int>{0}, 99),
        <int>[1, 2, 0],
      );
    });
  });

  group('拖拽映射', () {
    ZoomReorderController makeController() {
      final controller = ZoomReorderController();
      addTearDown(controller.dispose);
      return controller;
    }

    test('非拖拽态：槽位就是原始索引', () {
      final controller = makeController();
      controller.itemCount = 4;
      expect(controller.slotCount, 4);
      expect(controller.displaySlotOf(2), 2);
      expect(controller.isDragging, isFalse);
    });

    test('拖多条：余下条目补位，插入位避让出合集槽', () {
      final controller = makeController();
      controller.itemCount = 5;
      controller.selectedIndices = <int>{1, 3};
      controller.startDrag(1, Offset.zero);

      // remaining = [0, 2, 4]，初始插入位 = 1（原地附近）。
      expect(controller.dragging.value, <int>{1, 3});
      expect(controller.insertIndex, 1);
      expect(controller.slotCount, 4); // 3 个剩余 + 1 个合集槽
      expect(controller.displaySlotOf(1), isNull);
      expect(controller.displaySlotOf(3), isNull);
      expect(controller.displaySlotOf(0), 0);
      expect(controller.displaySlotOf(2), 2);
      expect(controller.displaySlotOf(4), 3);
    });

    test('拖未选中的条目只带走它自己', () {
      final controller = makeController();
      controller.itemCount = 4;
      controller.selectedIndices = <int>{0, 2};
      controller.startDrag(3, Offset.zero);
      expect(controller.dragging.value, <int>{3});
    });

    test('松手只回调一次，并复位为无拖拽态', () {
      final controller = makeController();
      controller.itemCount = 4;
      var calls = 0;
      Set<int>? received;
      int? receivedAt;
      controller.onReorder = (dragged, at) {
        calls++;
        received = dragged;
        receivedAt = at;
      };
      controller.startDrag(0, Offset.zero);
      controller.endDrag();
      expect(calls, 1);
      expect(received, <int>{0});
      expect(receivedAt, 0);
      expect(controller.isDragging, isFalse);
      expect(controller.reorderActive.value, isFalse);
      expect(controller.slotCount, 4);
    });

    test('取消拖拽不回调', () {
      final controller = makeController();
      controller.itemCount = 4;
      var calls = 0;
      controller.onReorder = (_, _) => calls++;
      controller.startDrag(0, Offset.zero);
      controller.cancelDrag();
      expect(calls, 0);
      expect(controller.isDragging, isFalse);
    });
  });

  group('槽位几何', () {
    const listGeometry = ZoomReorderGeometry(
      isGrid: false,
      columns: 1,
      contentWidth: 400,
      cardWidth: 400,
      cardHeight: 64,
      listHeight: 64,
      mainStride: 64,
      crossStride: 400,
      listStride: 64,
    );

    const gridGeometry = ZoomReorderGeometry(
      isGrid: true,
      columns: 3,
      contentWidth: 400,
      cardWidth: 100,
      cardHeight: 120,
      listHeight: 64,
      mainStride: 144,
      crossStride: 116,
      listStride: 64,
    );

    test('列表态按行换算插入位，并夹到剩余条目数', () {
      expect(listGeometry.insertIndexFor(const Offset(0, 0), 10), 0);
      expect(listGeometry.insertIndexFor(const Offset(0, 32), 10), 1);
      expect(listGeometry.insertIndexFor(const Offset(0, 200), 10), 3);
      expect(listGeometry.insertIndexFor(const Offset(0, 9999), 10), 10);
      expect(listGeometry.contentHeightFor(3), 192);
    });

    test('网格态按行列二维取整换算插入位', () {
      expect(gridGeometry.insertIndexFor(const Offset(0, 0), 9), 0);
      // 第 0 行第 1 列：不能把行内垂直位置乘上列数（旧公式会算成 2）。
      expect(gridGeometry.insertIndexFor(const Offset(116 * 1.5, 0), 9), 1);
      // 第 1 行第 0 列：旧公式 `fy*columns+fx` 会算出 5（飞到最右列）。
      expect(gridGeometry.insertIndexFor(const Offset(0, 144 * 1.5), 9), 3);
      expect(
        gridGeometry.insertIndexFor(
          const Offset(116 * 2 + 50, 144 * 2 + 60),
          9,
        ),
        8,
      );
      expect(gridGeometry.insertIndexFor(const Offset(9999, 9999), 9), 9);
      expect(gridGeometry.rectForSlot(4).left, 116);
      expect(gridGeometry.rectForSlot(4).top, 144);
      expect(gridGeometry.contentHeightFor(7), 3 * 144 - 24);
    });
  });
}
