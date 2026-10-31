import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 回归：**滚到列表底部时，双指捏合换档必须和点击档位换档落在同一个位置。**
///
/// 背景：捏合路径早期按目标档位的 `maxScrollOffsetFor()` 夹取目标滚动像素，而那个
/// 值是 **sliver 坐标**（内容总高 - 视口高，且不含外层 `SliverPadding`），像素坐标
/// 与它相差一个 `precede`（上方 header / padding 的高度）加尾部 padding。结果只有
/// "贴底"这一种情形会露馅：点击换档精确贴底，捏合却提前停下 `precede + 尾部 padding`
/// 那么多，整片内容偏下、最后一行被切掉一截。header 越高偏得越多。
///
/// 本测试用同一套布局分别跑两条路径，比对最终滚动像素与每一条的屏幕位置。

const int _kItemCount = 120;
const double _screenHeight = 800.0;

class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    required this.headerHeight,
    required this.initialZoom,
  });

  final double headerHeight;
  final double initialZoom;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final ScrollController controller = ScrollController();
  late double zoom = widget.initialZoom;

  void setZoom(double value) => setState(() => zoom = value);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, c) {
            return ZoomGestureLayer(
              zoomScale: zoom,
              onZoomScaleChanged: setZoom,
              enableHaptics: false,
              child: FolderZoomSliverBuilder(
                zoomScale: zoom,
                width: c.maxWidth,
                controller: controller,
                builder: (context, m) {
                  return CustomScrollView(
                    controller: controller,
                    slivers: [
                      if (widget.headerHeight > 0)
                        SliverToBoxAdapter(
                          child: SizedBox(height: widget.headerHeight),
                        ),
                      SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: folderContentHorizontalPadding(
                            isPortrait: m.isPortrait,
                            gridMorph: m.gridMorph,
                          ),
                          vertical: 16,
                        ),
                        sliver: SliverGrid(
                          gridDelegate: SliverAnimatedZoomGridDelegate(
                            metrics: m,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => ZoomItemScaffold(
                              key: ValueKey('item-$index'),
                              metrics: m,
                              titleText: 'Item $index',
                              subtitleText: 'S$index',
                              infoText: '3:00',
                            ),
                            childCount: _kItemCount,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

Map<int, double> _tops(WidgetTester tester) {
  final tops = <int, double>{};
  for (var i = 0; i < _kItemCount; i++) {
    final finder = find.byKey(ValueKey('item-$i'), skipOffstage: false);
    if (finder.evaluate().isEmpty) continue;
    final rect = tester.getRect(finder.first);
    if (rect.bottom < 1 || rect.top > _screenHeight - 1) continue;
    tops[i] = rect.top;
  }
  return tops;
}

Future<_HarnessState> _pump(
  WidgetTester tester,
  double headerHeight,
  double initialZoom,
) async {
  tester.view.physicalSize = const Size(400, _screenHeight);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(
    _Harness(
      key: key,
      headerHeight: headerHeight,
      initialZoom: initialZoom,
    ),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

void _jumpToBottom(_HarnessState state) {
  state.controller.jumpTo(state.controller.position.maxScrollExtent);
}

/// 双指径向张开（`zoomIn`）或靠拢，焦点固定在视口中心。
Future<void> _pinch(WidgetTester tester, {required bool zoomIn}) async {
  final g1 = await tester.startGesture(const Offset(150, 300), pointer: 11);
  final g2 = await tester.startGesture(const Offset(250, 400), pointer: 12);
  await tester.pump(const Duration(milliseconds: 16));
  for (var step = 1; step <= 6; step++) {
    final d = (zoomIn ? 1 : -1) * step * 8.0;
    await g1.moveTo(Offset(150 - d, 300 - d));
    await g2.moveTo(Offset(250 + d, 400 + d));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await g1.up();
  await g2.up();
  await tester.pumpAndSettle();
}

void main() {
  for (final headerHeight in <double>[0.0, 400.0]) {
    for (final zoomIn in <bool>[true, false]) {
      final String dir = zoomIn ? '放大' : '缩小';
      final double from =
          zoomIn ? kFolderZoomTierStandardList : kFolderZoomTierLargeGrid;
      final double to =
          zoomIn ? kFolderZoomTierLargeList : kFolderZoomTierMediumGrid;

      testWidgets('贴底换档：捏合$dir与点击落点一致'
          '（header=$headerHeight）', (tester) async {
        // ---- 路径 A：点击档位 ----
        final tap = await _pump(tester, headerHeight, from);
        _jumpToBottom(tap);
        await tester.pumpAndSettle();
        expect(
          tap.controller.offset,
          closeTo(tap.controller.position.maxScrollExtent, 0.5),
          reason: '前置条件：应已贴底',
        );

        tap.setZoom(to);
        await tester.pumpAndSettle();
        final double tapPixels = tap.controller.offset;
        final double tapMax = tap.controller.position.maxScrollExtent;
        final tapTops = _tops(tester);

        // ---- 路径 B：双指捏合 ----
        final pinch = await _pump(tester, headerHeight, from);
        _jumpToBottom(pinch);
        await tester.pumpAndSettle();
        await _pinch(tester, zoomIn: zoomIn);
        expect(
          pinch.zoom,
          closeTo(to, 1e-4),
          reason: '捏合应确认换到相邻档位（否则本用例没有可比性）',
        );
        final double pinchPixels = pinch.controller.offset;
        final pinchTops = _tops(tester);

        // 关键断言：两条路径的落点必须一致。
        expect(
          pinchPixels,
          closeTo(tapPixels, 1.0),
          reason: '贴底捏合$dir比点击少滚了 '
              '${(tapPixels - pinchPixels).toStringAsFixed(1)}px'
              '（点击=$tapPixels 捏合=$pinchPixels）→ 内容整体偏下',
        );
        expect(pinch.controller.position.maxScrollExtent, closeTo(tapMax, 1.0));

        for (final entry in tapTops.entries) {
          final double? pinchTop = pinchTops[entry.key];
          if (pinchTop == null) continue;
          expect(
            pinchTop,
            closeTo(entry.value, 1.0),
            reason: '条目 #${entry.key} 贴底捏合$dir后位置与点击差 '
                '${(pinchTop - entry.value).toStringAsFixed(1)}px',
          );
        }

        // 最后一条必须完整可见（贴着底部 padding），不能被切掉。
        expect(tapTops.keys, contains(_kItemCount - 1));
        expect(
          pinchTops[_kItemCount - 1],
          closeTo(tapTops[_kItemCount - 1]!, 1.0),
          reason: '最后一条贴底换档后被切/被推下',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
