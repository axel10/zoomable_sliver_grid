import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

void main() {
  group('直接拖拽与指示线排序测试', () {
    test('测试环境下 isNativeDragSupported 安全降级为 false', () {
      expect(ZoomReorderableSliverGrid.isNativeDragSupported, isFalse);
    });

    test('ZoomReorderGeometry 列表态单项插入位推算精确', () {
      const metrics = FolderZoomLayoutMetrics(
        targetZoomScale: 0.0,
        animatedZoomScale: 0.0,
        gridMorph: 0.0,
        compactMorph: 0.0,
        animatedGridCols: 1.0,
        animatedGridTextHeight: 0.0,
        animatedListExtent: 56.0,
        targetCardWidth: 800.0,
      );
      final geometry = ZoomReorderGeometry.from(metrics, 800.0);

      expect(geometry.isGrid, isFalse);
      expect(geometry.columns, 1);
      final stride = geometry.listStride;

      // 在第 0 项上半部分 -> 插入位 0
      expect(
        geometry.insertIndexFor(Offset(200, stride * 0.2), 10),
        0,
      );
      // 在第 0 项与第 1 项交界处稍下 -> 插入位 1
      expect(
        geometry.insertIndexFor(Offset(200, stride * 0.8), 10),
        1,
      );
      // 在第 5 项附近 -> 插入位 5
      expect(
        geometry.insertIndexFor(Offset(200, stride * 5.1), 10),
        5,
      );
      // 超过总数 -> 限制在总数
      expect(
        geometry.insertIndexFor(Offset(200, stride * 20), 10),
        10,
      );
    });

    test('ZoomReorderGeometry 网格态插入位推算精确', () {
      const metrics = FolderZoomLayoutMetrics(
        targetZoomScale: 1.0,
        animatedZoomScale: 1.0,
        gridMorph: 1.0,
        compactMorph: 0.0,
        animatedGridCols: 4.0,
        animatedGridTextHeight: 40.0,
        animatedListExtent: 56.0,
        targetCardWidth: 200.0,
      );
      final geometry = ZoomReorderGeometry.from(metrics, 1200.0);

      expect(geometry.isGrid, isTrue);
      expect(geometry.columns, greaterThan(1));

      // 第 0 行第 0 列 -> 插入位 0
      expect(
        geometry.insertIndexFor(const Offset(10, 10), 20),
        0,
      );
      // 第 0 行第 1 列 -> 插入位 1
      expect(
        geometry.insertIndexFor(Offset(geometry.crossStride * 1.2, 10), 20),
        1,
      );
    });

    test('applyReorder 单条直接拖拽重排结果正确', () {
      final original = ['A', 'B', 'C', 'D', 'E'];

      // 把 A (index 0) 拖到 C (index 2) 之前
      final reordered1 = ZoomReorderController.applyReorder(
        original,
        {0},
        2,
      );
      expect(reordered1, ['B', 'C', 'A', 'D', 'E']);

      // 把 E (index 4) 拖到开头 (index 0)
      final reordered2 = ZoomReorderController.applyReorder(
        original,
        {4},
        0,
      );
      expect(reordered2, ['E', 'A', 'B', 'C', 'D']);

      // 拖到原地 (无变动)
      final reordered3 = ZoomReorderController.applyReorder(
        original,
        {2},
        2,
      );
      expect(reordered3, ['A', 'B', 'C', 'D', 'E']);
    });
  });
}
