import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

void main() {
  group('ZoomReorderController 异步重排', () {
    ZoomReorderController makeController() {
      final controller = ZoomReorderController();
      addTearDown(controller.dispose);
      return controller;
    }

    test('异步成功：状态流转与并发拖拽拦截', () async {
      final controller = makeController();
      controller.itemCount = 4;

      final completer = Completer<bool>();
      Set<int>? received;
      int? receivedAt;

      controller.onReorderAsync = (dragged, at) {
        received = dragged;
        receivedAt = at;
        return completer.future;
      };

      controller.startDrag(0, Offset.zero);
      expect(controller.isDragging, isTrue);

      controller.endDrag();
      expect(controller.isDragging, isFalse);
      expect(received, <int>{0});
      expect(receivedAt, 0);

      // 处于异步保存中状态
      expect(controller.isAsyncReordering.value, isTrue);

      // 异步保存期间，禁止再次起拖
      controller.startDrag(1, Offset.zero);
      expect(controller.isDragging, isFalse);

      // 完成异步保存
      completer.complete(true);
      await pumpEventQueue();

      // 状态恢复，可以再次起拖
      expect(controller.isAsyncReordering.value, isFalse);
      controller.startDrag(1, Offset.zero);
      expect(controller.isDragging, isTrue);
      controller.cancelDrag();
    });

    test('异步返回 false：触发 onReorderError 且状态恢复', () async {
      final controller = makeController();
      controller.itemCount = 4;

      Object? capturedError;
      controller.onReorderError = (error, stack) {
        capturedError = error;
      };

      final completer = Completer<bool>();
      controller.onReorderAsync = (dragged, at) => completer.future;

      controller.startDrag(0, Offset.zero);
      controller.endDrag();
      expect(controller.isAsyncReordering.value, isTrue);

      completer.complete(false);
      await pumpEventQueue();

      expect(controller.isAsyncReordering.value, isFalse);
      expect(capturedError, isA<StateError>());
    });

    test('异步抛出异常：触发 onReorderError 且状态恢复', () async {
      final controller = makeController();
      controller.itemCount = 4;

      Object? capturedError;
      controller.onReorderError = (error, stack) {
        capturedError = error;
      };

      final completer = Completer<bool>();
      controller.onReorderAsync = (dragged, at) => completer.future;

      controller.startDrag(0, Offset.zero);
      controller.endDrag();
      expect(controller.isAsyncReordering.value, isTrue);

      completer.completeError(Exception('Network timeout'));
      await pumpEventQueue();

      expect(controller.isAsyncReordering.value, isFalse);
      expect(capturedError.toString(), contains('Network timeout'));
    });
  });

  group('ZoomReorderableSliverGrid 异步视觉状态', () {
    testWidgets('渲染异步保存中指示器并在完成后消失', (tester) async {
      final controller = ZoomReorderController();
      addTearDown(controller.dispose);

      final completer = Completer<bool>();
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

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                ZoomReorderableSliverGrid(
                  metrics: metrics,
                  width: 400.0,
                  itemCount: 4,
                  controller: controller,
                  onReorderAsync: (dragged, at) => completer.future,
                  itemBuilder: (context, index) => Container(
                    key: ValueKey('item_$index'),
                    color: Colors.blue,
                    child: Text('Item $index'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // 默认没有指示器
      expect(find.byType(LinearProgressIndicator), findsNothing);

      // 手动触发一次异步派发
      controller.dispatchAsyncReorder({0}, 1);
      await tester.pump();

      // 此时展示默认指示器
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // 异步完成
      completer.complete(true);
      await tester.pumpAndSettle();

      // 指示器消失
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });
}
