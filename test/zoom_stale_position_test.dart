import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 回归测试：`Scrollable` 在中途换掉 `ScrollPosition` 之后，换档仍要补偿滚动。
///
/// `_ScrollableState.didChangeDependencies()` 会 `_updatePosition()`：老位置被
/// `scheduleMicrotask(dispose)`，新位置顶上，而**两者共用同一个 `ScrollContext`**
/// （`mounted` 依旧为 true），老位置的 `pixels` 从此冻结。安卓真机上 MediaQuery
/// （系统栏 / 刘海 insets）启动后还会再变一次，正好踩中这条路径；macOS 窗口尺寸
/// 一帧就稳定，所以只在安卓上看得到。
///
/// 一旦缓存里留着那个僵尸位置，换档时的"像素 ↔ sliver 坐标"换算会崩：目标像素
/// 被算成负数、夹到 0，滚动补偿全程失效 —— 屏幕上就是**所有条目**跟着几何层一起
/// 滑动，而不是"只有共同可见条目位移，其余原地淡入淡出"。

class _Harness extends StatefulWidget {
  const _Harness({super.key, required this.initialZoom});

  final double initialZoom;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final ScrollController controller = ScrollController();
  late double zoom = widget.initialZoom;
  double touchSlop = 18.0;

  void setZoom(double value) => setState(() => zoom = value);

  /// 改一个 [Scrollable] 依赖的 MediaQuery 字段，强制它换掉 `ScrollPosition`。
  void bumpMediaQuery() => setState(() => touchSlop += 1.0);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            gestureSettings: DeviceGestureSettings(touchSlop: touchSlop),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              // 故意不传 controller：走"从渲染树里找 ScrollPosition"的兜底路径，
              // 安卓真机上就是这条路径踩的坑。
              return FolderZoomSliverBuilder(
                zoomScale: zoom,
                width: c.maxWidth,
                builder: (context, metrics) {
                  return CustomScrollView(
                    controller: controller,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        sliver: SliverGrid(
                          gridDelegate: SliverAnimatedZoomGridDelegate(
                            metrics: metrics,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => ZoomItemScaffold(
                              key: ValueKey('item-$index'),
                              metrics: metrics,
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
  }
}

/// 当前可见条目：索引 -> 顶部 y（视口 800 高）。
Map<int, double> _visible(WidgetTester tester) {
  final visible = <int, double>{};
  for (var i = 0; i < 120; i++) {
    final finder = find.byKey(ValueKey('item-$i'), skipOffstage: false);
    if (finder.evaluate().isEmpty) continue;
    final rect = tester.getRect(finder.first);
    if (rect.bottom < 1 || rect.top > 799) continue;
    visible[i] = rect.top;
  }
  return visible;
}

Finder _item(int index) => find.byKey(ValueKey('item-$index'));

void main() {
  testWidgets('ScrollPosition 被换掉后，换档仍然补偿滚动、条目不再整体滑动', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      _Harness(key: key, initialZoom: kFolderZoomTierStandardList),
    );
    await tester.pumpAndSettle();
    final state = key.currentState!;
    final controller = state.controller;

    controller.jumpTo(controller.position.maxScrollExtent * 0.4);
    await tester.pumpAndSettle();

    // 关键前置条件：位置真的被换掉了（否则这条测试什么都没测到）。
    final oldPosition = controller.position;
    state.bumpMediaQuery();
    await tester.pumpAndSettle();
    expect(
      identical(controller.position, oldPosition),
      isFalse,
      reason: 'MediaQuery 变化应触发 Scrollable 换掉 ScrollPosition',
    );

    final before = _visible(tester);
    final pixelsBefore = controller.offset;
    final anchorIndex = before.keys.firstWhere(
      (i) => before[i]! <= 400 && before[i]! + 80 > 400,
      orElse: () => before.keys.reduce(
        (a, b) => (before[a]! - 400).abs() <= (before[b]! - 400).abs() ? a : b,
      ),
    );
    final anchorTopBefore = before[anchorIndex]!;

    // 跑完整段换档，逐帧检查：焦点条目最多移动一个槽位增量，
    // 一旦滚动补偿失效，它会跟着几何层滑出去几百像素。
    state.setZoom(kFolderZoomTierLargeList);
    for (var frame = 0; frame < 16; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      final finder = _item(anchorIndex);
      expect(finder, findsOneWidget, reason: '第 $frame 帧焦点条目消失了');
      final top = tester.getRect(finder).top;
      expect(
        (top - anchorTopBefore).abs(),
        lessThan(40.0),
        reason: '第 $frame 帧焦点条目位移 ${top - anchorTopBefore}px，'
            '说明滚动补偿没有跟上几何变化（所有条目都会一起滑动）',
      );
    }
    await tester.pumpAndSettle();

    expect(
      (controller.offset - pixelsBefore).abs(),
      greaterThan(500.0),
      reason: '换档必须补偿滚动：pixels 应随内容变长而明显变化',
    );
  });
}
