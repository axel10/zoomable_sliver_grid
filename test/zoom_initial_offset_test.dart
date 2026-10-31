import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 回归测试：恢复滚动位置（如 initialScrollOffset / PageStorageKey）进入页面时，
/// 首帧能正确计算出当前视口内的可见条目索引，而不是因为首帧 contentCount 未测量
/// 而将视口顶部误 clamp 到负数导致只构建顶部几条或整屏空白。
void main() {
  testWidgets('带 initialScrollOffset 初始化时，首帧正确渲染视口内的条目', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = ScrollController(initialScrollOffset: 1000);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              return FolderZoomSliverBuilder(
                zoomScale: kFolderZoomTierStandardList,
                width: constraints.maxWidth,
                controller: controller,
                builder: (context, metrics) {
                  return CustomScrollView(
                    controller: controller,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        sliver: SliverGrid(
                          gridDelegate: SliverAnimatedZoomGridDelegate(
                            metrics: metrics,
                            section: 'test-section',
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => ZoomItemScaffold(
                              key: ValueKey('item-$index'),
                              metrics: metrics,
                              section: 'test-section',
                              titleText: 'Item $index',
                              subtitleText: 'S$index',
                              infoText: '3:00',
                            ),
                            childCount: 120,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );

    // 仅 pump 1 帧，验证首帧布局
    await tester.pump();

    // 在 offset 1000（行高 80 + 间距 0），视口 800 范围内，预期可见条目为 12~22 左右
    expect(find.byKey(const ValueKey('item-12')), findsOneWidget);
    expect(find.byKey(const ValueKey('item-15')), findsOneWidget);
    // 顶部条目（如 0~5）此时应在视口上方，未被渲染
    expect(find.byKey(const ValueKey('item-0')), findsNothing);
  });
}
