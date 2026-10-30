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
