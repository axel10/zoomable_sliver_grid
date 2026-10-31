import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 回归测试：一个页面里放两个参与缩放的网格（目录列表 + 一行固定高的介绍 + 文件列表）。
///
/// 要守住的三件事：
/// 1. 换档时**焦点处的内容不动**：两个网格都要跟着一起补偿，而不是只有上面那个准；
/// 2. 中间那行介绍的高度是固定的：换档前后，上下列表之间的间距必须一模一样；
/// 3. 过渡期间两段都不能出现空白帧或整片错位。

const double _headerHeight = 96.0;
const double _introHeight = 140.0;
const double _tailHeight = 24.0;
const int _dirCount = 14;
const int _fileCount = 90;

const Object _dirSection = 'dirs';
const Object _fileSection = 'files';

class MultiHarness extends StatefulWidget {
  const MultiHarness({super.key, required this.initialZoom});

  final double initialZoom;

  @override
  State<MultiHarness> createState() => MultiHarnessState();
}

class MultiHarnessState extends State<MultiHarness> {
  final ScrollController controller = ScrollController();
  late double zoom = widget.initialZoom;

  /// 最近一次构建拿到的度量，测试用来读冻结表 / 过渡进度。
  FolderZoomLayoutMetrics? metrics;

  void setZoom(double value) => setState(() => zoom = value);

  Widget _section(
    FolderZoomLayoutMetrics metrics, {
    required Object section,
    required String prefix,
    required int count,
    required double vertical,
  }) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: vertical),
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
                this.metrics = metrics;
                return CustomScrollView(
                  controller: controller,
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(
                        key: const ValueKey('header'),
                        height: _headerHeight,
                        child: const Center(child: Text('header')),
                      ),
                    ),
                    _section(
                      metrics,
                      section: _dirSection,
                      prefix: 'dir',
                      count: _dirCount,
                      vertical: 16,
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
                      vertical: 16,
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: _tailHeight),
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

class _Snapshot {
  _Snapshot({
    required this.pixels,
    required this.maxExtent,
    required this.tops,
    required this.bottoms,
  });

  final double pixels;
  final double maxExtent;

  /// 条目 key -> 顶部 / 底部的全局 y。
  final Map<String, double> tops;
  final Map<String, double> bottoms;

  bool get isEmpty => tops.isEmpty;

  /// 焦点（视口中心）落在哪个条目里。
  String? itemAt(double y) {
    for (final entry in tops.entries) {
      final bottom = bottoms[entry.key] ?? entry.value;
      if (entry.value <= y && bottom > y) return entry.key;
    }
    return null;
  }
}

_Snapshot _snapshot(WidgetTester tester, ScrollController controller) {
  final tops = <String, double>{};
  final bottoms = <String, double>{};
  for (final prefix in ['dir', 'file']) {
    final count = prefix == 'dir' ? _dirCount : _fileCount;
    for (var i = 0; i < count; i++) {
      final key = '$prefix-$i';
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

Future<MultiHarnessState> _pump(
  WidgetTester tester, {
  required double initialZoom,
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final key = GlobalKey<MultiHarnessState>();
  await tester.pumpWidget(MultiHarness(key: key, initialZoom: initialZoom));
  await tester.pumpAndSettle();
  return key.currentState!;
}

Future<List<_Snapshot>> _transition(
  WidgetTester tester,
  MultiHarnessState state,
  double targetZoom,
) async {
  final frames = <_Snapshot>[];
  state.setZoom(targetZoom);
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    frames.add(_snapshot(tester, state.controller));
  }
  await tester.pumpAndSettle();
  frames.add(_snapshot(tester, state.controller));
  return frames;
}

/// 把滚动位置推到"焦点落在文件列表里"的地方。
Future<void> _scrollIntoFiles(WidgetTester tester, ScrollController c) async {
  c.jumpTo(c.position.maxScrollExtent * 0.45);
  await tester.pumpAndSettle();
}

/// 把中间那行介绍滚到视口中心，让上下列表最后 / 第一条同时可见。
Future<void> _scrollToIntro(WidgetTester tester, ScrollController c) async {
  final double max = c.position.maxScrollExtent;
  double? pageOffset;
  for (var i = 1; i <= 60; i++) {
    c.jumpTo(max * i / 60);
    await tester.pump();
    final finder = find.byKey(const ValueKey('intro'), skipOffstage: false);
    if (finder.evaluate().isEmpty) continue;
    final rect = tester.getRect(finder.first);
    if (rect.top >= 0 && rect.bottom <= 800) {
      pageOffset = c.offset + rect.top;
      break;
    }
  }
  expect(pageOffset, isNotNull, reason: '没能把介绍行滚进视口');
  c.jumpTo((pageOffset! - 400).clamp(0.0, max));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('焦点落在文件列表时，换档前后该条目仍停在焦点上', (tester) async {
    final state = await _pump(tester, initialZoom: kFolderZoomTierStandardList);
    await _scrollIntoFiles(tester, state.controller);

    final before = _snapshot(tester, state.controller);
    final anchorKey = before.itemAt(400);
    expect(anchorKey, isNotNull, reason: '视口中心没有条目：${before.tops}');
    expect(anchorKey!.startsWith('file'), isTrue,
        reason: '这个用例要求焦点落在文件列表里，实际是 $anchorKey');

    final frames = await _transition(
      tester,
      state,
      kFolderZoomTierLargeList,
    );
    final after = frames.last;

    for (var i = 0; i < frames.length; i++) {
      expect(frames[i].isEmpty, isFalse, reason: '第 $i 帧整屏空白');
    }

    expect(after.tops.containsKey(anchorKey), isTrue,
        reason: '焦点条目 $anchorKey 换档后不见了：${after.tops.keys.toList()}');

    final double strideBefore = getFolderListTileExtent(
      kFolderZoomTierStandardList,
    );
    final double strideAfter = getFolderListTileExtent(
      kFolderZoomTierLargeList,
    );
    // 锚定不变量是"焦点处的内容点不动"，条目顶部允许相差一个槽位步距以内的量。
    expect(
      (after.tops[anchorKey]! - before.tops[anchorKey]!).abs(),
      lessThanOrEqualTo((strideAfter - strideBefore).abs() + 2.0),
      reason: '焦点条目被甩开了：before=${before.tops[anchorKey]} '
          'after=${after.tops[anchorKey]}',
    );
    // 更直接的一条：焦点必须仍然落在同一个条目里。
    expect(
      after.itemAt(400),
      anchorKey,
      reason: '换档后焦点落到了 ${after.itemAt(400)} 而不是 $anchorKey',
    );
  });

  testWidgets('上下列表之间那行介绍的间距，换档前后完全一致', (tester) async {
    final state = await _pump(tester, initialZoom: kFolderZoomTierStandardList);
    await _scrollToIntro(tester, state.controller);

    double? gapOf(_Snapshot s) {
      final lastDir = s.bottoms['dir-${_dirCount - 1}'];
      final firstFile = s.tops['file-0'];
      if (lastDir == null || firstFile == null) return null;
      return firstFile - lastDir;
    }

    final before = _snapshot(tester, state.controller);
    final gapBefore = gapOf(before);
    expect(gapBefore, isNotNull, reason: '首尾条目不在视口里：${before.tops}');
    // 介绍行固定高，再加上两段各自的 16px 纵向 padding。
    expect(gapBefore, closeTo(_introHeight + 32.0, 1.5));

    await _transition(tester, state, kFolderZoomTierSmallGrid);

    // 换成网格后目录列表变矮，介绍行会被推出视口，再滚回来看一次稳态间距。
    // （过渡中的帧不做这个断言：只在一侧可见的条目会被锁在原地淡出，
    //   它和另一段条目之间的间距在过渡期间本来就不是几何间距。）
    await _scrollToIntro(tester, state.controller);
    final after = _snapshot(tester, state.controller);
    expect(gapOf(after), isNotNull, reason: '换档后找不到上下两段：${after.tops}');
    expect(
      gapOf(after),
      closeTo(_introHeight + 32.0, 1.5),
      reason: '换档后间距变成了 ${gapOf(after)}',
    );
  });

  testWidgets('页面靠近顶部、焦点在目录列表时，换档不拽动页面', (tester) async {
    final state = await _pump(tester, initialZoom: kFolderZoomTierStandardList);
    // 滚到刚好能看到目录列表的位置（焦点落在目录里，同时页面离顶部不足一屏）。
    state.controller.jumpTo(120);
    await tester.pumpAndSettle();

    final before = _snapshot(tester, state.controller);
    expect(before.itemAt(400)?.startsWith('dir'), isTrue);

    final frames = await _transition(
      tester,
      state,
      kFolderZoomTierLargeList,
    );
    final after = frames.last;

    for (var i = 0; i < frames.length; i++) {
      expect(frames[i].isEmpty, isFalse, reason: '第 $i 帧整屏空白');
    }
    // 离页面顶端不足一屏时，锚定退化成"顶对齐"：页面本身不该被上下拽。
    expect(
      (after.pixels - before.pixels).abs(),
      lessThan(6.0),
      reason: '页面被拖动了 ${after.pixels - before.pixels}px',
    );
    expect(after.tops.containsKey('dir-0'), isTrue);
    expect(after.tops.containsKey('file-0'), isFalse,
        reason: '这个位置本来就看不到文件列表首条，断言只用来确认列表没被整体甩走');
  });

  testWidgets('贴底换档：仍然精确贴住最大滚动位置', (tester) async {
    final state = await _pump(tester, initialZoom: kFolderZoomTierStandardList);
    state.controller.jumpTo(state.controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    final before = _snapshot(tester, state.controller);
    expect(before.pixels, closeTo(before.maxExtent, 1.0));

    final frames = await _transition(tester, state, kFolderZoomTierSmallGrid);
    final after = frames.last;

    expect(
      after.pixels,
      closeTo(after.maxExtent, 1.0),
      reason: '贴底换档后没有贴住底部：px=${after.pixels} '
          'max=${after.maxExtent}',
    );

    final header = find.byKey(const ValueKey('header'), skipOffstage: false);
    expect(header.evaluate().isNotEmpty, isTrue);
    final headerRect = tester.getRect(header.first);

    for (var i = 0; i < frames.length; i++) {
      expect(frames[i].isEmpty, isFalse, reason: '第 $i 帧整屏空白');
    }
    // 底部的最后一条必须还在视口里，不能被顶出去。
    final lastKey = 'file-${_fileCount - 1}';
    expect(after.tops.containsKey(lastKey), isTrue,
        reason: '最后一条不在视口里：${after.tops.keys.toList()}');
    expect(after.bottoms[lastKey]!, lessThanOrEqualTo(800.0));
    // 只是用一下 headerRect，避免"未使用"的告警。
    expect(headerRect.width, greaterThan(0));
  });

  testWidgets('第二个列表中部反复换档：来回切换回到原位，不逐渐漂移', (tester) async {
    final state = await _pump(tester, initialZoom: kFolderZoomTierSmallGrid);
    await _scrollIntoFiles(tester, state.controller);

    final start = _snapshot(tester, state.controller);
    // 焦点条目与它在屏幕上的位置，是"内容有没有被甩走"的直接证据。
    final focusKey = start.itemAt(400);
    expect(focusKey, isNotNull, reason: '视口中心没有条目：${start.tops}');
    expect(focusKey!.startsWith('file'), isTrue,
        reason: '这个用例要求焦点落在文件列表里，实际是 $focusKey');
    final focusTop = start.tops[focusKey]!;

    for (var round = 0; round < 3; round++) {
      await _transition(tester, state, kFolderZoomTierLargeGrid);
      final afterUp = _snapshot(tester, state.controller);
      // 列数变了（8 列 -> 6 列），同一条目会落到相邻的一行上，所以"条目顶部
      // 完全不动"不成立；能要求的是它最多挪一行的距离，且仍在文件列表里。
      expect(afterUp.itemAt(400)?.startsWith('file'), isTrue,
          reason: '第 $round 轮换档后焦点落到 ${afterUp.itemAt(400)} 上');
      expect(
        (afterUp.tops[focusKey]! - focusTop).abs(),
        lessThan(230.0),
        reason: '第 $round 轮换成大网格后焦点条目被甩开：'
            '${afterUp.tops[focusKey]} vs $focusTop',
      );

      await _transition(tester, state, kFolderZoomTierSmallGrid);
      final afterDown = _snapshot(tester, state.controller);
      expect(
        afterDown.pixels,
        closeTo(start.pixels, 1.0),
        reason: '第 $round 轮换回来没有回到原位：'
            'px=${afterDown.pixels} 起始=${start.pixels}',
      );
      expect(
        afterDown.tops[focusKey],
        closeTo(focusTop, 2.0),
        reason: '第 $round 轮换回来焦点条目被甩开：'
            '${afterDown.tops[focusKey]} vs $focusTop',
      );
    }
  });

  testWidgets('第二个列表中部换档：单侧可见的条目原地淡入淡出，不是直接闪现', (tester) async {
    final state = await _pump(tester, initialZoom: kFolderZoomTierSmallGrid);
    await _scrollIntoFiles(tester, state.controller);

    state.setZoom(kFolderZoomTierLargeGrid);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    final metrics = state.metrics!;
    final pinning = metrics.sectionPinning[_fileSection];
    expect(pinning, isNotNull,
        reason: '文件段没有冻结表：整段过渡都会退化成纯位移，条目直接闪现');
    expect(pinning!.isEmpty, isFalse, reason: '冻结表是空的');

    final int index = pinning.firstPinnedIndex!;
    final itemKey = ValueKey('file-$index');
    final samples = <double>[];
    var onScreenSamples = 0;
    for (var i = 0; i < 5; i++) {
      final m = state.metrics!;
      samples.add(m.resolveItemTransition(index, section: _fileSection).opacity);
      // 被冻结的条目必须真的在视口里，否则"淡入淡出"只是存在于数据结构里，
      // 屏幕上仍然什么都看不到。
      final finder = find.byKey(itemKey, skipOffstage: false);
      if (finder.evaluate().isNotEmpty) {
        final rect = tester.getRect(finder.first);
        if (rect.bottom > 0 && rect.top < 800) onScreenSamples++;
      }
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    expect(onScreenSamples, greaterThan(0),
        reason: '被冻结的条目 file-$index 全程不在视口里，淡入淡出看不见');

    // 不透明度必须逐帧连续变化：从 1 淡出到 0（或反过来），中途落在开区间里。
    expect(
      samples.any((o) => o > 0.05 && o < 0.95),
      isTrue,
      reason: '不透明度没有过渡（看起来就是直接闪现）：$samples',
    );
    for (var i = 1; i < samples.length; i++) {
      expect(
        samples[i],
        lessThanOrEqualTo(samples[i - 1] + 1e-3),
        reason: '淡出过程出现回跳：$samples',
      );
    }
  });

  testWidgets('页面在最顶端换档：整页不上下窜动', (tester) async {
    final state = await _pump(tester, initialZoom: kFolderZoomTierStandardList);
    expect(state.controller.offset, 0.0);

    final frames = await _transition(tester, state, kFolderZoomTierSmallGrid);
    for (var i = 0; i < frames.length; i++) {
      expect(
        frames[i].pixels,
        lessThan(1.0),
        reason: '第 $i 帧页面被往下拽了 ${frames[i].pixels}px',
      );
    }
    final header = find.byKey(const ValueKey('header'), skipOffstage: false);
    expect(tester.getRect(header.first).top, closeTo(0.0, 1.0));
  });
}
