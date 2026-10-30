# Zoomable Sliver Grid

A high-performance Flutter package for seamless, physics-based list-to-grid zoom transitions in sliver scroll views.

## Features

- **Continuous Geometric Morphing**: Interpolates sliver items smoothly between single-column lists and multi-column grids via convex combination layers without jarring layout jumps or orbit artifacts.
- **Scroll & Viewport Anchoring**: Automatically anchors the top visible item during tier transitions so users never lose their place.
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
              builder: (context, metrics) {
                return CustomScrollView(
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
