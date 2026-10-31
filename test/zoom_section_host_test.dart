import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 一页多段时必须只有一个 [FolderZoomSliverBuilder]：各段自己建 builder 会让
/// 滚动补偿互相顶走（上游那一段在下游的 tracker 里不存在）。
///
/// 这里守住两件事：
/// 1. 祖先有 `FolderZoomMetricsScope` 时，`FolderZoomSectionHost` 直接复用页面度量，
///    不再自建 builder；
/// 2. 没有祖先时，`FolderZoomSectionHost` 自己退化成宿主（单列表旧行为）。
void main() {
  Widget section(String label) {
    return SliverToBoxAdapter(
      child: SizedBox(height: 48, child: Text(label)),
    );
  }

  testWidgets('多段页面共用一个 builder，且各段拿到同一份度量', (tester) async {
    final seen = <FolderZoomLayoutMetrics>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              return FolderZoomSliverBuilder(
                zoomScale: kFolderZoomTierStandardList,
                width: constraints.maxWidth,
                builder: (context, metrics) {
                  return CustomScrollView(
                    slivers: [
                      FolderZoomSectionHost(
                        zoomScale: kFolderZoomTierStandardList,
                        width: constraints.maxWidth,
                        builder: (context, sectionMetrics) {
                          seen.add(sectionMetrics);
                          return section('folders');
                        },
                      ),
                      FolderZoomSectionHost(
                        zoomScale: kFolderZoomTierStandardList,
                        width: constraints.maxWidth,
                        builder: (context, sectionMetrics) {
                          seen.add(sectionMetrics);
                          return section('songs');
                        },
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

    expect(find.byType(FolderZoomSliverBuilder), findsOneWidget);
    expect(seen, hasLength(2));
    expect(identical(seen.first, seen.last), isTrue);
    expect(find.text('folders'), findsOneWidget);
    expect(find.text('songs'), findsOneWidget);
  });

  testWidgets('没有祖先时每段自己就是宿主', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              FolderZoomSectionHost(
                zoomScale: kFolderZoomTierStandardList,
                width: 400,
                builder: (context, metrics) => section('alone'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(FolderZoomSliverBuilder), findsOneWidget);
    expect(find.text('alone'), findsOneWidget);
  });
}
