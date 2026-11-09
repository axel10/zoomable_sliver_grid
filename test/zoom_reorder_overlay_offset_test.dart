import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

void main() {
  testWidgets('嵌套 Navigator 与左侧边栏 Padding 下，拖拽浮层位置贴合原位不右偏', (tester) async {
    const sidebarWidth = 216.0;
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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
          body: Row(
            children: [
              const SizedBox(width: sidebarWidth),
              Expanded(
                child: Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (context) => Scaffold(
                      body: CustomScrollView(
                        slivers: [
                          ZoomReorderableSliverGrid(
                            metrics: metrics,
                            width: 1200.0 - sidebarWidth,
                            itemCount: 4,
                            showHandles: true,
                            onReorder: (_, __) {},
                            itemBuilder: (context, index) => Container(
                              color: Colors.blue,
                              child: Text('Item $index'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 找到第一个条目和它的手柄
    final handleFinder = find.byType(ZoomReorderHandle).first;
    expect(handleFinder, findsOneWidget);
    final handleCenter = tester.getCenter(handleFinder);

    // 起拖
    final gesture = await tester.startGesture(handleCenter);
    await gesture.moveTo(handleCenter + const Offset(5.0, 50.0));
    await tester.pump(const Duration(milliseconds: 100));

    final previewFinder = find.byType(ZoomReorderPreview);
    expect(previewFinder, findsOneWidget);

    final previewRect = tester.getRect(previewFinder);

    // 手柄位置应该包含在 preview 矩形内部（而不是 preview 跑到手柄右边 216px 之外）
    final currentPointer = handleCenter + const Offset(5.0, 50.0);
    expect(
      previewRect.contains(currentPointer),
      isTrue,
      reason: '浮层应该覆盖在抓握点周围，而不是向右偏移了侧边栏宽度',
    );

    // 确认浮层的左边界没有偏出到 sidebarWidth * 2 之后
    // 第一个条目在 (sidebarWidth) 附近，宽度约 230，加上 5px 移动，浮层 left 应该在 sidebarWidth + 5 左右
    expect(previewRect.left, lessThan(sidebarWidth + 50.0));

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
