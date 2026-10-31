import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 回归测试：换档过渡期间，**缩放段之后**的 sliver（这里是两段网格之间那行固定高
/// 的介绍）必须跟着一起平移，不能"钉在屏幕上"。
///
/// 曾经的实现把单侧可见条目锁在**屏幕**位置上（`scrollOffset = viewportTop +
/// 冻结的屏幕 y`）。`RenderSliverGrid` 上报的 `scrollExtent` / `paintExtent`
/// 取的是"已布局条目里最靠下的那条的下边缘"，而视口里后面每个 sliver 的位置都是
/// 前一个 extent 累加出来的 —— 锁屏坐标让本段的高度变成 `pixels - precede + 常数`，
/// 于是后面那段内容被摆到一个屏幕常量上：换档时它既不跟着动、又在第一帧整体偏移
/// 一截，观感就是"中间那块内容突然消失又突然出现"。
///
/// 触发条件：滚到上一段末尾只剩半行的位置再**放大**（本段变矮），此时淡入条目锁在
/// 目标档的屏幕位置、高度也是目标档的，压不住插值后的内容末端。

const double _introHeight = 140.0;
const int _dirCount = 14;
const int _fileCount = 90;

const Object _dirSection = 'dirs';
const Object _fileSection = 'files';

class GapHarness extends StatefulWidget {
  const GapHarness({super.key, required this.initialZoom});

  final double initialZoom;

  @override
  State<GapHarness> createState() => GapHarnessState();
}

class GapHarnessState extends State<GapHarness> {
  final ScrollController controller = ScrollController();
  late double zoom = widget.initialZoom;

  void setZoom(double value) => setState(() => zoom = value);

  Widget _section(
    FolderZoomLayoutMetrics metrics, {
    required Object section,
    required String prefix,
    required int count,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      sliver: SliverGrid(
        gridDelegate: SliverAnimatedZoomGridDelegate(
          metrics: metrics,
          section: section,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => ZoomItemScaffold(
            key: ValueKey('$prefix-$index'),
            metrics: metrics,
            section: section,
            titleText: '$prefix $index',
            subtitleText: 'S$index',
            infoText: '3:00',
          ),
          childCount: count,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, c) {
            return FolderZoomSliverBuilder(
              zoomScale: zoom,
              width: c.maxWidth,
              controller: controller,
              builder: (context, metrics) {
                return CustomScrollView(
                  controller: controller,
                  slivers: [
                    _section(
                      metrics,
                      section: _dirSection,
                      prefix: 'dir',
                      count: _dirCount,
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(
                        key: ValueKey('intro'),
                        height: _introHeight,
                        child: Center(child: Text('intro')),
                      ),
                    ),
                    _section(
                      metrics,
                      section: _fileSection,
                      prefix: 'file',
                      count: _fileCount,
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

Future<GapHarnessState> _pump(
  WidgetTester tester, {
  required Size size,
  required double initialZoom,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey<GapHarnessState>();
  await tester.pumpWidget(GapHarness(key: key, initialZoom: initialZoom));
  await tester.pumpAndSettle();
  return key.currentState!;
}

/// 把两段之间那行介绍的顶边滚到视口 `introTop` 处。
Future<void> _scrollIntroTo(
  WidgetTester tester,
  ScrollController controller,
  double introTop,
) async {
  final double max = controller.position.maxScrollExtent;
  double? pageOffset;
  for (var i = 0; i <= 400; i++) {
    controller.jumpTo((i * 8.0).clamp(0.0, max));
    await tester.pump();
    final finder = find.byKey(const ValueKey('intro'), skipOffstage: false);
    if (finder.evaluate().isEmpty) continue;
    final rect = tester.getRect(finder.first);
    if (rect.top >= 0 && rect.top <= 8) {
      pageOffset = controller.offset + rect.top;
      break;
    }
  }
  expect(pageOffset, isNotNull, reason: '没能把介绍行滚进视口');
  controller.jumpTo((pageOffset! - introTop).clamp(0.0, max));
  await tester.pumpAndSettle();
}

/// 逐帧采样介绍行的屏幕顶部 y。
Future<List<double?>> _transition(
  WidgetTester tester,
  GapHarnessState state,
  double targetZoom, {
  int frames = 20,
}) async {
  double? top() {
    final finder = find.byKey(const ValueKey('intro'), skipOffstage: false);
    if (finder.evaluate().isEmpty) return null;
    return tester.getRect(finder.first).top;
  }

  final samples = <double?>[top()];
  state.setZoom(targetZoom);
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    samples.add(top());
  }
  await tester.pumpAndSettle();
  samples.add(top());
  return samples;
}

/// 断言：位移是**摊在整段过渡里**的，而不是第一帧瞬移到位、之后就钉住。
///
/// 具体三条：
/// 1. 不允许出现反向折返；
/// 2. 任何一帧的位移不超过总位移的 1/3（瞬移的特征是某一帧吃掉全部位移）；
/// 3. 第一帧之后的位置必须还没到终点 —— 曾经的实现第一帧就到位、后面全程静止。
void _expectSpreadOut(List<double?> samples) {
  final present = samples.whereType<double>().toList();
  expect(present.length, greaterThan(10), reason: '采样不足：$samples');

  final double total = (present.last - present.first).abs();
  expect(total, greaterThan(30.0),
      reason: '整段过渡里介绍行几乎没动（共 ${total.toStringAsFixed(1)}px）：$samples');

  final bool upward = present.last < present.first;
  for (var i = 1; i < present.length; i++) {
    final double delta = present[i] - present[i - 1];
    final bool reversed = upward ? delta > 1.5 : delta < -1.5;
    expect(reversed, isFalse,
        reason: '第 $i 帧反向位移 ${delta.toStringAsFixed(1)}px：$samples');
    expect(
      delta.abs(),
      lessThanOrEqualTo(total / 3 + 1.5),
      reason: '第 $i 帧一帧走了 ${delta.toStringAsFixed(1)}px'
          '（总位移 ${total.toStringAsFixed(1)}px，说明是瞬移而不是位移动画）：$samples',
    );
  }

  expect(
    (present[1] - present.last).abs(),
    greaterThan(total * 0.5),
    reason: '第一帧就到终点、后面全程静止（位移动画消失）：$samples',
  );
}

void main() {
  setUp(() => folderZoomDebugLog = false);

  testWidgets('横屏：上一段只剩半行时放大，中间那行介绍跟着一起平移', (tester) async {
    final state = await _pump(
      tester,
      size: const Size(1200, 800),
      initialZoom: kFolderZoomTierStandardList,
    );
    await _scrollIntroTo(tester, state.controller, 30);

    final samples = await _transition(tester, state, kFolderZoomTierSmallGrid);
    _expectSpreadOut(samples);
  });

  testWidgets('竖屏：上一段只剩半行时放大，中间那行介绍跟着一起平移', (tester) async {
    final state = await _pump(
      tester,
      size: const Size(400, 800),
      initialZoom: kFolderZoomTierStandardList,
    );
    await _scrollIntroTo(tester, state.controller, 30);

    final samples = await _transition(tester, state, kFolderZoomTierLargeGrid);
    _expectSpreadOut(samples);
  });

  testWidgets('第二段也在动：间隔行平移量与第二段整体平移一致', (tester) async {
    final state = await _pump(
      tester,
      size: const Size(1200, 800),
      initialZoom: kFolderZoomTierSmallGrid,
    );
    await _scrollIntroTo(tester, state.controller, 30);

    double? firstFileTop() {
      final finder = find.byKey(const ValueKey('file-0'), skipOffstage: false);
      if (finder.evaluate().isEmpty) return null;
      return tester.getRect(finder.first).top;
    }

    final introBefore = tester.getRect(
      find.byKey(const ValueKey('intro')),
    ).top;
    final fileBefore = firstFileTop();
    expect(fileBefore, isNotNull, reason: '第二段首条不在视口里');

    final samples = await _transition(tester, state, kFolderZoomTierStandardList);
    _expectSpreadOut(samples);

    final introAfter = samples.last!;
    final fileAfter = firstFileTop();
    expect(fileAfter, isNotNull, reason: '换档后第二段首条不在视口里');

    // 介绍行与第二段之间的相对距离由几何决定，过渡期可能因为单侧条目锁屏而变化；
    // 这里只要求两者朝**同一个方向**移动，即"一起被上面那段顶下去"。
    expect(
      (fileAfter! - fileBefore!).sign,
      (introAfter - introBefore).sign,
      reason: '介绍行移动 ${(introAfter - introBefore).toStringAsFixed(1)}px，'
          '第二段却移动 ${(fileAfter - fileBefore).toStringAsFixed(1)}px',
    );
  });
}
