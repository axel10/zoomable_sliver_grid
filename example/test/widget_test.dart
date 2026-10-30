// 示例 App 的冒烟测试。

import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

void main() {
  testWidgets('demo renders and zoom button is present', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ZoomableGridExampleApp());
    await tester.pump();

    expect(find.text('Zoomable Sliver Grid'), findsOneWidget);
    expect(find.byType(ZoomButton), findsOneWidget);
  });
}
