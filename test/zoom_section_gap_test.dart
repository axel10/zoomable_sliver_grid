import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 段与段之间的固定高度（`SliverPadding` 的 `top`、中间那行介绍、页头）
/// **必须与档位无关**。
///
/// 这类高度不参与缩放，包里按「常量 + 上游各段高度」外推下游段在页面里的位置
/// （`FolderZoomViewportTracker.gapBefore` 只在单层稳态量一次）。一旦它随
/// `gridMorph` 变化，换档收尾那一帧切回真实布局就要一次性补差额 —— 屏幕上表现为
/// 「动画结束的瞬间整体往下沉一点」。
///
/// 项目侧（`lib/widgets/folder_content_slivers.dart`、`remote_server_slivers.dart`）
/// 因此把段首内边距固定成 8，而不是 `lerp(0, 8, gridMorph)`。
///
/// 这个文件把两侧都钉住：
/// - `恒定 gap：收尾不跳` —— 项目采用的形态；
/// - `gap 随档位变：收尾必跳` —— 已知限制。如果哪天它**失败**了，说明包里已经能
///   处理随档位变化的段间距（按档位记录 gap / 页面声明 gap），那时就可以把项目侧
///   的常量改回动画值，并删掉这条用例。

const double _bannerHeight = 190.0;
const double _sectionHeaderHeight = 60.0;
const double _tailHeight = 160.0;

const Object _folderSection = 'folder-root.folders';
const Object _serverSection = 'folder-root.servers';

/// 过渡时长（`zoom_layout_utils.dart` 里 `_controller` 的 260ms）。
const Duration _transitionDuration = Duration(milliseconds: 260);

/// 采样点：动画走完约 92%，此时 `easeOutCubic` 已到 99.95%，剩余位移可忽略。
const Duration _lastFrameAt = Duration(milliseconds: 240);

class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    required this.initialZoom,
    required this.folderCount,
    required this.serverCount,
    required this.crossAxisExtent,
    required this.gapFollowsMorph,
  });

  final double initialZoom;
  final int folderCount;
  final int serverCount;
  final double? crossAxisExtent;

  /// 段首内边距是否随档位变化（`lerp(0, 8, gridMorph)`）；`false` 时恒为 8。
  final bool gapFollowsMorph;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final ScrollController controller = ScrollController();
  late double zoom = widget.initialZoom;

  void setZoom(double value) => setState(() => zoom = value);

  Widget _section(
    FolderZoomLayoutMetrics metrics, {
    required Object section,
    required String prefix,
    required int count,
    required double bottom,
  }) {
    final double top = widget.gapFollowsMorph
        ? lerpDouble(0.0, 8.0, metrics.gridMorph)!
        : 8.0;
    return SliverPadding(
      padding: EdgeInsets.only(top: top, bottom: bottom, left: 16, right: 16),
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
              width: widget.crossAxisExtent ?? c.maxWidth,
              controller: controller,
              builder: (context, metrics) {
                return CustomScrollView(
                  controller: controller,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    const SliverToBoxAdapter(
                      child: SizedBox(height: _bannerHeight),
                    ),
                    _section(
                      metrics,
                      section: _folderSection,
                      prefix: 'dir',
                      count: widget.folderCount,
                      bottom: 16,
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(
                        key: ValueKey('section-header'),
                        height: _sectionHeaderHeight,
                      ),
                    ),
                    _section(
                      metrics,
                      section: _serverSection,
                      prefix: 'srv',
                      count: widget.serverCount,
                      bottom: _tailHeight,
                    ),
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

/// 一帧里三个参照物的屏幕位置：段头、目录首项、云端首项。
typedef _Sample = ({double header, double dir0, double srv0});

_Sample _sample(WidgetTester tester) {
  double topOf(String key) {
    final finder = find.byKey(ValueKey(key), skipOffstage: false);
    if (finder.evaluate().isEmpty) return double.nan;
    return tester.getRect(finder.first).top;
  }

  return (
    header: topOf('section-header'),
    dir0: topOf('dir-0'),
    srv0: topOf('srv-0'),
  );
}

/// 跑一次「列表 → 网格」，返回动画最后一帧与收尾稳态之间的位移。
Future<_Sample> _measureSettleShift(
  WidgetTester tester, {
  required Size size,
  required int folderCount,
  required int serverCount,
  required bool gapFollowsMorph,
  double scrollFraction = 0.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey<_HarnessState>();
  await tester.pumpWidget(
    _Harness(
      key: key,
      initialZoom: kFolderZoomTierStandardList,
      folderCount: folderCount,
      serverCount: serverCount,
      crossAxisExtent: size.width,
      gapFollowsMorph: gapFollowsMorph,
    ),
  );
  await tester.pumpAndSettle();

  final state = key.currentState!;
  if (scrollFraction > 0) {
    state.controller.jumpTo(
      state.controller.position.maxScrollExtent * scrollFraction,
    );
    await tester.pumpAndSettle();
  }

  state.setZoom(kFolderZoomTierLargeGrid);
  await tester.pump();

  var last = _sample(tester);
  var spent = Duration.zero;
  while (spent < _lastFrameAt) {
    await tester.pump(const Duration(milliseconds: 16));
    spent += const Duration(milliseconds: 16);
    last = _sample(tester);
  }

  await tester.pumpAndSettle();
  final settled = _sample(tester);

  expect(
    spent,
    greaterThanOrEqualTo(_lastFrameAt),
    reason: '动画最后一帧应当在 ${_lastFrameAt.inMilliseconds}ms 之后采到',
  );
  expect(
    spent,
    lessThan(_transitionDuration),
    reason: '采样点必须还在过渡中（早于 ${_transitionDuration.inMilliseconds}ms）',
  );

  return (
    header: settled.header - last.header,
    dir0: settled.dir0 - last.dir0,
    srv0: settled.srv0 - last.srv0,
  );
}

void main() {
  setUp(() => folderZoomGeometryProbe = false);

  group('段首内边距恒定（项目采用的形态）', () {
    testWidgets('短页面：列表→网格，收尾不跳', (tester) async {
      final shift = await _measureSettleShift(
        tester,
        size: const Size(1200, 800),
        folderCount: 3,
        serverCount: 2,
        gapFollowsMorph: false,
      );
      expect(shift.header.abs(), lessThan(1.5), reason: '段头位移 $shift');
      expect(shift.dir0.abs(), lessThan(1.5), reason: '目录首项位移 $shift');
      expect(shift.srv0.abs(), lessThan(1.5), reason: '云端首项位移 $shift');
    });

    testWidgets('长页面（滚到中段）：列表→网格，收尾不跳', (tester) async {
      final shift = await _measureSettleShift(
        tester,
        size: const Size(1200, 800),
        folderCount: 12,
        serverCount: 6,
        gapFollowsMorph: false,
        scrollFraction: 0.5,
      );
      expect(shift.header.abs(), lessThan(1.5), reason: '段头位移 $shift');
      expect(shift.dir0.abs(), lessThan(1.5), reason: '目录首项位移 $shift');
      expect(shift.srv0.abs(), lessThan(1.5), reason: '云端首项位移 $shift');
    });
  });

  group('段首内边距随档位变化（已知限制，项目里禁止这么写）', () {
    testWidgets('长页面：列表→网格，收尾必跳，且下游段被多顶一份', (tester) async {
      final shift = await _measureSettleShift(
        tester,
        size: const Size(1200, 800),
        folderCount: 12,
        serverCount: 6,
        gapFollowsMorph: true,
        scrollFraction: 0.5,
      );
      // 被锚定的目录首项自己不动，但它下面的段头与云端列表分别补上「本段 gap」与
      // 「上游 gap + 本段 gap」的差额（实测 +8 / +16）。
      expect(shift.dir0.abs(), lessThan(1.5), reason: '锚定条目应当不动 $shift');
      expect(shift.header, greaterThan(6.0), reason: '段头应当被顶下 8px $shift');
      expect(
        shift.srv0,
        greaterThan(shift.header + 4.0),
        reason: '下游段要多顶一份上游 gap（8 + 8） $shift',
      );
    });
  });
}
