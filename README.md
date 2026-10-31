# Zoomable Sliver Grid

A high-performance Flutter package for seamless, physics-based list-to-grid zoom transitions in sliver scroll views.

## Features

- **Continuous Geometric Morphing**: Interpolates sliver items smoothly between single-column lists and multi-column grids via convex combination layers without jarring layout jumps or orbit artifacts.
- **Scroll & Viewport Anchoring**: Focal-point anchoring — the content under the viewport focus (or under your fingers while pinching) stays put across tier changes, so the same items stay on screen instead of the list jumping to a different place.
- **Single Subtree Item Scaffold**: `ZoomItemScaffold` handles layout transitions, corner radiuses, multi-selection checkboxes, and typography interpolation within a single persistent widget tree.
- **Cross-Platform Gestures**:
  - Desktop mouse/trackpad: `Ctrl / Cmd + Scroll` cluster stepping.
  - Trackpad: Smooth two-finger pinch gesture with scale tracking.
  - Touchscreen: Responsive two-finger pinch with haptic feedback.
- **Zero Third-Party Dependencies**: Built purely on the Flutter SDK.

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

class MyZoomableList extends StatefulWidget {
  const MyZoomableList({super.key});

  @override
  State<MyZoomableList> createState() => _MyZoomableListState();
}

class _MyZoomableListState extends State<MyZoomableList> {
  double _zoomScale = kFolderZoomTierStandardList;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zoomable Grid'),
        actions: [
          ZoomButton(
            zoomScale: _zoomScale,
            onZoomScaleChanged: (scale) => setState(() => _zoomScale = scale),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return ZoomGestureLayer(
            zoomScale: _zoomScale,
            onZoomScaleChanged: (scale) => setState(() => _zoomScale = scale),
            child: FolderZoomSliverBuilder(
              zoomScale: _zoomScale,
              width: constraints.maxWidth,
              // 传入滚动控制器，换档时才能换算并补偿滚动距离。
              // 不传时会自动从子树里找到 ScrollPosition（同一 builder 下有多个滚动视图时请显式传入）。
              controller: _scrollController,
              builder: (context, metrics) {
                return CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: folderContentHorizontalPadding(
                          isPortrait: metrics.isPortrait,
                          gridMorph: metrics.gridMorph,
                        ),
                      ),
                      sliver: SliverGrid(
                        gridDelegate: SliverAnimatedZoomGridDelegate(metrics: metrics),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return ZoomItemScaffold(
                              metrics: metrics,
                              titleText: 'Item #$index',
                              subtitleText: 'Subtitle #$index',
                              cover: ZoomItemCover(
                                metrics: metrics,
                                child: Container(color: Colors.blueAccent),
                              ),
                            );
                          },
                          childCount: 100,
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
    );
  }
}
```

## How scroll distance is derived

Tier changes drastically change item geometry, so "keep item #42 at the same pixel" is the wrong
invariant — it collapses at the end of the list and makes the whole viewport slide. Instead the
package keeps **the content point under the focus fixed**:

```text
f         = focus height in the viewport (0.5 = center, or the pinch midpoint)
c         = scrollTop + f                    // content coordinate under the focus
i, r      = the item containing c, and how far into its slot it lands (0..1)
targetTop = offset_B(i) + r * stride_B - f   // scroll position for the new tier
```

Everything else follows from this:

- **Top / bottom edges** collapse the focus toward `0` / the bottom of the viewport, so the two ends
  degenerate into "top-aligned" / "bottom-aligned" — no clamping artifacts, the last row stays flush.
- **Bottom edge** is solved from the difference in total content height between the two tiers, so
  outer `SliverPadding` cannot introduce a drift.
- **Scroll and layout share one eased progress value**, and multi-tier jumps are solved directly from
  start → target (no per-tier accumulation).
- **While pinching** the focus is the two-finger midpoint, so the content under your fingers does not
  slide — that is what makes a pinch feel like a zoom instead of a drag.
- **Only items visible in both tiers are translated.** Items that are visible in just one of the two
  layouts are pinned to their own tier's screen position and faded in / out in place
  (`FolderZoomItemPinning`). The classification is computed **once, when the transition starts**:
  visibility is a boolean and the scroll position moves thousands of pixels mid-transition, so
  re-evaluating it every frame would flip items back and forth and make them teleport.

The practical effect: the items visible before a tier change are, as far as the new layout allows,
still visible after it, and the ones that must fade in/out are the fewest possible.

## Grid below other slivers

The grid does not have to start at the top of the page. Putting a banner, a `SliverPersistentHeader`
or a `SliverAppBar` above it is supported:

```dart
CustomScrollView(
  slivers: [
    SliverAppBar(pinned: true, title: Text('Library')),
    SliverToBoxAdapter(child: FeaturedBanner()),
    SliverPadding(padding: ..., sliver: SliverGrid(gridDelegate: SliverAnimatedZoomGridDelegate(...))),
  ],
)
```

What matters is the coordinate frame: `SliverConstraints.scrollOffset` is **clamped to 0** by Flutter
whenever the sliver's leading edge is still *below* the viewport's leading edge, so it cannot be used
as "the scroll position of the grid". The package derives the real value instead:

```text
leadingGap = max(0, viewportMainAxisExtent - remainingPaintExtent)   // header + outer padding
viewportTop = scrollOffset - leadingGap                              // negative while the header is visible
viewportBottom = viewportTop + viewportMainAxisExtent
```

With that, `viewportTop = pixels - precedingContentExtent` holds everywhere, which is what the anchor
math, `viewportHeight`, `maxScrollExtent` clamping and the pinch path all rely on. Consequences worth
knowing:

- While part of the header is still on screen, the focus is the viewport center as usual, and a tier
  change scrolls the page (and the header) as needed to keep the content under the focus in place.
- At the very top of the page (`pixels == 0`) there is no room to scroll up, so a tier change degrades
  to "keep the grid's first item where it is" and never yanks the page down.
- Bottom edge detection / clamping is exact with a header in place, because
  `maxScrollOffsetFor` is computed from the real viewport height rather than from the paint extent.

## Several grids in one page

A page can carry more than one zoomable grid — a folder list, a fixed-height intro row, then a file
list, for example. They share one `FolderZoomSliverBuilder` (column count and font sizes depend only
on width + tier, so they are identical by construction) and each one declares its own identity:

```dart
FolderZoomSliverBuilder(
  zoomScale: zoom,
  width: constraints.maxWidth,
  controller: controller,
  builder: (context, metrics) => CustomScrollView(
    controller: controller,
    slivers: [
      section('folders', metrics, folders.length),
      SliverToBoxAdapter(child: IntroCard()),           // 高度固定，不参与缩放
      section('files', metrics, files.length),
    ],
  ),
)

SliverGrid section(String id, FolderZoomLayoutMetrics metrics, int count) {
  return SliverGrid(
    gridDelegate: SliverAnimatedZoomGridDelegate(metrics: metrics, section: id),
    delegate: SliverChildBuilderDelegate(
      (context, index) => ZoomItemScaffold(
        metrics: metrics,
        section: id,                                     // 与 delegate 保持一致
        titleText: 'Item $index',
      ),
      childCount: count,
    ),
  );
}
```

Both `section` values must be distinct, and the same value must be passed to `ZoomItemScaffold` —
each section numbers its items from `0`, so the fade-in/fade-out classification has to be looked up
per section.

The scroll solve moves to **page coordinates**:

```text
gapBefore_k   = precede_k - Σ_{j<k} extent_j          // 不随档位变化的那部分（页头 / 介绍行 / padding）
pageStart_k   = gapBefore_k + Σ_{j<k} extent_j(L)
targetPixels  = pageStart_anchor(L) + localTargetTop(L)     // 焦点锚定
              = pageEnd(L) + tail - viewportHeight          // 贴底
              = pixels                                      // 贴顶
```

`Σ_{j<k} extent_j(L)` is the whole point: when the folder list shrinks from 1120px to 412px, the file
list below it moves up by 708px in page space. Without that term the scroll compensation keeps the
focused item fixed *inside its own section* while the section itself slides — the visible symptom is
"the lower list jumps by one section-height the moment the tier changes". Gaps between sections are
zoom-invariant, which is what lets `gapBefore` be measured once and reused across tiers.

Notes:

- Only one section can be the anchor (the one under the focus). Everything below it still moves; that
  is unavoidable and exactly what keeps both lists' content continuous.
- A section is pruned from the tracker after two layout passes without visiting it, so conditionally
  removing a list does not leave a stale extent behind.
- During the transition a section's own items morph in its own coordinate frame, so the two lists
  animate on the same clock with no cross-talk.

