import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

void main() {
  test('FolderZoomTier snapping and stepping', () {
    expect(snapFolderZoomScale(0.0), equals(kFolderZoomTierMinimalList));
    expect(snapFolderZoomScale(0.15), equals(kFolderZoomTierCompactList));
    expect(snapFolderZoomScale(1.0), equals(kFolderZoomTierLargeGrid));

    final nextTier = stepFolderZoomScale(kFolderZoomTierMinimalList, 1);
    expect(nextTier, equals(kFolderZoomTierCompactList));

    final prevTier = stepFolderZoomScale(kFolderZoomTierLargeGrid, -1);
    expect(prevTier, equals(kFolderZoomTierMediumGrid));
  });

  test('FolderZoomTier classification', () {
    expect(FolderZoomTier.minimalList.isGrid, isFalse);
    expect(FolderZoomTier.compactList.isGrid, isFalse);
    expect(FolderZoomTier.standardList.isGrid, isFalse);
    expect(FolderZoomTier.largeList.isGrid, isFalse);
    expect(FolderZoomTier.smallGrid.isGrid, isTrue);
    expect(FolderZoomTier.mediumGrid.isGrid, isTrue);
    expect(FolderZoomTier.largeGrid.isGrid, isTrue);
  });
}
