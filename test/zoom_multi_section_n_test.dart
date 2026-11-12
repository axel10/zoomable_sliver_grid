import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 三段 / 四段（不只是两段）同页的回归测试。
///
/// 要守住的三件事（与两段版本同一套不变量，只是段数更多）：
/// 1. 焦点落在中间某段时，换档后焦点处的内容不动；
/// 2. 段与段之间那层固定高的分隔不随档位变化；
/// 3. 反复来回换档不逐渐漂移。

const double _headerHeight = 96.0;
const double _dividerHeight = 56.0;
const double _tailHeight = 24.0;

const List<int> _counts3 = <int>[12, 70, 40];
const List<int> _counts4 = <int>[12, 70, 40, 30];

String _prefix(int section) => 's$section';

class SectionHarness extends StatefulWidget {
  const SectionHarness({
    super.key,
    required this.initialZoom,
    required this.counts,
  });

  final double initialZoom;
  final List<int> counts;

  @override
  State<SectionHarness> createState() => SectionHarnessState();
}

class SectionHarnessState extends State<SectionHarness> {
  final ScrollController controller = ScrollController();
  late double zoom = widget.initialZoom;
  FolderZoomLayoutMetrics? metrics;

  void setZoom(double value) => setState(() => zoom = value);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final counts = widget.counts;
    return MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, c) {
            return FolderZoomSliverBuilder(
              zoomScale: zoom,
              width: c.maxWidth,
              controller: controller,
              builder: (context, metrics) {
                this.metrics = metrics;
                final slivers = <Widget>[
                  const SliverToBoxAdapter(
                    child: SizedBox(
                      key: ValueKey('header'),
                      height: _headerHeight,
                      child: Center(child: Text('header')),
                    ),
                  ),
                ];
                for (var s = 0; s < counts.length; s++) {
                  if (s > 0) {
                    slivers.add(
                      SliverToBoxAdapter(
                        child: SizedBox(
                          key: ValueKey('divider-$s'),
                          height: _dividerHeight,
                        ),
                      ),
                    );
                  }
                  slivers.add(
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: SliverAnimatedZoomGridDelegate(
                          metrics: metrics,
                          section: _prefix(s),
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => ZoomItemScaffold(
                            key: ValueKey('${_prefix(s)}-$index'),
                            metrics: metrics,
                            section: _prefix(s),
                            titleText: '${_prefix(s)} $index',
                            subtitleText: 'S$index',
                            infoText: '3:00',
                          ),
                          childCount: counts[s],
                        ),
                      ),
                    ),
                  );
                }
                slivers.add(
                  const SliverToBoxAdapter(
                    child: SizedBox(height: _tailHeight),
                  ),
                );
                return CustomScrollView(
                  controller: controller,
                  slivers: slivers,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Snapshot {
  _Snapshot({
    required this.pixels,
    required this.maxExtent,
    required this.tops,
    required this.bottoms,
  });

  final double pixels;
  final double maxExtent;
  final Map<String, double> tops;
  final Map<String, double> bottoms;

  bool get isEmpty => tops.isEmpty;

  /// 包含高度 [y] 的条目；落在行间距里时取下一行最靠左的那个。
  ///
  /// 网格一行有多个条目、同一行内部横向全等，所以"焦点处是哪一条"本身是多值的，
  /// 断言只能落在**行**上（见 [rowTopAt]）。
  String? itemAt(double y) {
    String? best;
    double bestTop = double.infinity;
    for (final entry in tops.entries) {
      final bottom = bottoms[entry.key] ?? entry.value;
      final bool contains = entry.value <= y && bottom > y;
      final double top = contains ? entry.value : (entry.value >= y ? entry.value : double.infinity);
      if (top < bestTop) {
        bestTop = top;
        best = entry.key;
      }
      if (contains) return entry.key;
    }
    return best;
  }

  /// 包含高度 [y] 的那一行（或下一行）的顶边。
  double? rowTopAt(double y) {
    final String? key = itemAt(y);
    return key == null ? null : tops[key];
  }
}

_Snapshot _snapshot(
  WidgetTester tester,
  ScrollController controller,
  List<int> counts,
) {
  final tops = <String, double>{};
  final bottoms = <String, double>{};
  for (var s = 0; s < counts.length; s++) {
    for (var i = 0; i < counts[s]; i++) {
      final key = '${_prefix(s)}-$i';
      final finder = find.byKey(ValueKey(key), skipOffstage: false);
      if (finder.evaluate().isEmpty) continue;
      final rect = tester.getRect(finder.first);
      if (rect.bottom < 0 || rect.top > 800) continue;
      tops[key] = rect.top;
      bottoms[key] = rect.bottom;
    }
  }
  return _Snapshot(
    pixels: controller.offset,
    maxExtent: controller.position.maxScrollExtent,
    tops: tops,
    bottoms: bottoms,
  );
}

Future<SectionHarnessState> _pump(
  WidgetTester tester, {
  required double initialZoom,
  required List<int> counts,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey<SectionHarnessState>();
  await tester.pumpWidget(
    SectionHarness(key: key, initialZoom: initialZoom, counts: counts),
  );
  await tester.pumpAndSettle();
  return key.currentState!;
}

Future<List<_Snapshot>> _transition(
  WidgetTester tester,
  SectionHarnessState state,
  double targetZoom,
) async {
  final frames = <_Snapshot>[];
  state.setZoom(targetZoom);
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    frames.add(_snapshot(tester, state.controller, state.widget.counts));
  }
  await tester.pumpAndSettle();
  frames.add(_snapshot(tester, state.controller, state.widget.counts));
  return frames;
}

/// 把视口中心滚到第 [section] 段**中部**的条目上。
///
/// 刻意避开段的起始 / 结束边界：焦点正好落在两段的接缝上时，"焦点处的内容"
/// 同时在两段里，换档后落到哪一段都可能，那不是锚定失败。
Future<void> _scrollFocusInto(
  WidgetTester tester,
  SectionHarnessState state,
  int section,
) async {
  final c = state.controller;
  final double max = c.position.maxScrollExtent;
  final int count = state.widget.counts[section];
  final int lo = (count * 0.25).floor();
  final int hi = (count * 0.75).ceil();
  for (var i = 1; i <= 200; i++) {
    c.jumpTo(max * i / 200);
    await tester.pump();
    final snap = _snapshot(tester, c, state.widget.counts);
    final at = snap.itemAt(400);
    if (at == null) continue;
    final parts = at.split('-');
    if (parts[0] != _prefix(section)) continue;
    final int index = int.parse(parts[1]);
    if (index < lo || index > hi) continue;
    await tester.pumpAndSettle();
    return;
  }
  fail('没能把焦点滚进第 $section 段中部');
}

void main() {
  for (final counts in <List<int>>[_counts3, _counts4]) {
    final label = '${counts.length} 段';

    testWidgets('$label：焦点落在中间那段，换档后焦点内容不动、全程不空白', (tester) async {
      final state = await _pump(
        tester,
        initialZoom: kFolderZoomTierSmallGrid,
        counts: counts,
      );
      final int middle = counts.length ~/ 2;
      await _scrollFocusInto(tester, state, middle);

      final before = _snapshot(tester, state.controller, counts);
      final anchorKey = before.itemAt(400);
      expect(anchorKey, isNotNull, reason: '视口中心没有条目：${before.tops}');
      expect(anchorKey!.startsWith('${_prefix(middle)}-'), isTrue,
          reason: '用例要求焦点落在第 $middle 段，实际是 $anchorKey');
      final double anchorRowTop = before.tops[anchorKey]!;

      final frames = await _transition(
        tester,
        state,
        kFolderZoomTierLargeGrid,
      );
      final after = frames.last;

      for (var i = 0; i < frames.length; i++) {
        expect(frames[i].isEmpty, isFalse, reason: '第 $i 帧整屏空白');
      }

      // 焦点处的内容必须还在同一段里 —— 换档后焦点若落到相邻那段，说明上游各段
      // 的高度没有被计入补偿，整页错位了一整段的高度。
      expect(
        after.itemAt(400)?.startsWith('${_prefix(middle)}-'),
        isTrue,
        reason: '$label 换档后焦点落到 ${after.itemAt(400)}，越出了第 $middle 段',
      );
      // 列数变了（8 列 -> 6 列），同一条目会落到相邻的行，所以只能要求"焦点那一行
      // 最多挪一行的距离"，而不是像素级不动。
      expect(
        after.rowTopAt(400),
        isNotNull,
        reason: '$label 换档后视口中心一行条目都没有',
      );
      expect(
        (after.rowTopAt(400)! - anchorRowTop).abs(),
        lessThan(230.0),
        reason: '$label 焦点那一行被甩开：'
            '${after.rowTopAt(400)} vs $anchorRowTop',
      );
    });

    testWidgets('$label：段间分隔的高度换档前后一致', (tester) async {
      final state = await _pump(
        tester,
        initialZoom: kFolderZoomTierStandardList,
        counts: counts,
      );

      /// 第 [section] 段最后一条底边到下一段第一条顶边之间的距离。
      double? gapOf(_Snapshot s, int section) {
        final last = s.bottoms['${_prefix(section)}-${counts[section] - 1}'];
        final first = s.tops['${_prefix(section + 1)}-0'];
        if (last == null || first == null) return null;
        return first - last;
      }

      /// 把某两段之间那层分隔滚到**视口中间**，好让上下两段的边界条目都完整可见。
      ///
      /// 停在接缝刚露头的位置不行：那时下一段第一条只露出一部分，量到的不是
      /// 稳定的几何间距。
      Future<void> scrollToSeam(int section) async {
        final c = state.controller;
        final double max = c.position.maxScrollExtent;
        final finder = find.byKey(
          ValueKey('divider-${section + 1}'),
          skipOffstage: false,
        );
        for (var i = 1; i <= 200; i++) {
          c.jumpTo(max * i / 200);
          await tester.pump();
          if (finder.evaluate().isEmpty) continue;
          final rect = tester.getRect(finder.first);
          if (rect.top >= 120 && rect.bottom <= 680) {
            await tester.pumpAndSettle();
            return;
          }
        }
        fail('没能把第 $section 段与第 ${section + 1} 段的接缝滚进视口');
      }

      for (var section = 0; section < counts.length - 1; section++) {
        await scrollToSeam(section);
        final before = _snapshot(tester, state.controller, counts);
        final gapBefore = gapOf(before, section);
        expect(gapBefore, isNotNull, reason: '接缝 $section 两侧不在视口里');
        // 分隔固定高 + 两段各自的 16px 纵向 padding。
        expect(
          gapBefore,
          closeTo(_dividerHeight + 32.0, 1.5),
          reason: '$label 接缝 $section 的初始间距是 $gapBefore',
        );

        await _transition(tester, state, kFolderZoomTierSmallGrid);
        await scrollToSeam(section);
        final after = _snapshot(tester, state.controller, counts);
        expect(
          gapOf(after, section),
          isNotNull,
          reason: '$label 换档后接缝 $section 两侧找不到条目',
        );
        expect(
          gapOf(after, section),
          closeTo(_dividerHeight + 32.0, 1.5),
          reason: '$label 接缝 $section 换档后间距变成 ${gapOf(after, section)}',
        );
      }
    });

    testWidgets('$label：中间段反复来回换档回到原位，不逐渐漂移', (tester) async {
      final state = await _pump(
        tester,
        initialZoom: kFolderZoomTierSmallGrid,
        counts: counts,
      );
      final int middle = counts.length ~/ 2;
      await _scrollFocusInto(tester, state, middle);

      final start = _snapshot(tester, state.controller, counts);
      final focusKey = start.itemAt(400);
      expect(focusKey, isNotNull, reason: '视口中心没有条目');
      final focusRowTop = start.tops[focusKey]!;

      for (var round = 0; round < 3; round++) {
        await _transition(tester, state, kFolderZoomTierLargeGrid);
        final up = _snapshot(tester, state.controller, counts);
        expect(up.itemAt(400)?.startsWith('${_prefix(middle)}-'), isTrue,
            reason: '$label 第 $round 轮换成大网格后焦点落到 ${up.itemAt(400)}');

        await _transition(tester, state, kFolderZoomTierSmallGrid);
        final down = _snapshot(tester, state.controller, counts);
        expect(
          down.pixels,
          closeTo(start.pixels, 1.5),
          reason: '$label 第 $round 轮换回来没有回到原位：'
              'px=${down.pixels} 起始=${start.pixels}',
        );
        expect(
          down.rowTopAt(400),
          closeTo(focusRowTop, 2.5),
          reason: '$label 第 $round 轮换回来焦点那一行被甩开：'
              '${down.rowTopAt(400)} vs $focusRowTop',
        );
      }
    });

    // 页面顶部 / 底部一屏内换档时，焦点高度 `f` 会随 `pageTop` 渐变；两档解出来的
    // `f` 不同（实测 400.0 与 375.9）。如果"解换档目标"和"settle 后反取锚点"用的不是
    // 同一个 `f`，往返一次就净丢 `|f_new - f_old|` 那么长的一段内容，反复换档持续漂移。
    testWidgets('$label：页面顶部一屏内（焦点渐变区）往返换档，不漂移', (tester) async {
      final state = await _pump(
        tester,
        initialZoom: kFolderZoomTierSmallGrid,
        counts: counts,
      );

      // 滚到"离顶部不足一屏"的位置 —— 这正是 `_resolveFocusY` 的 topBlend 生效的区间。
      final c = state.controller;
      final double max = c.position.maxScrollExtent;
      var found = false;
      for (var i = 1; i <= 200; i++) {
        c.jumpTo(max * i / 200);
        await tester.pump();
        if (c.offset < 640.0 || c.offset > 900.0) continue;
        if (_snapshot(tester, c, counts).itemAt(400) == null) continue;
        await tester.pumpAndSettle();
        found = true;
        break;
      }
      expect(found, isTrue, reason: '没找到"顶部一屏内、焦点有内容"的起点');

      final double startPixels = c.offset;
      for (var round = 0; round < 3; round++) {
        await _transition(tester, state, kFolderZoomTierLargeGrid);
        await _transition(tester, state, kFolderZoomTierSmallGrid);
        expect(
          c.offset,
          closeTo(startPixels, 1.0),
          reason: '$label 第 $round 轮往返没回到原位：'
              'px=${c.offset} 起始=$startPixels',
        );
      }
    });
  }
}
