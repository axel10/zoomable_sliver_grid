## 0.0.2

* **焦点锚定取代顶部锚定**：换档时保持"视口焦点（默认中心，捏合时为双指中点）处的内容"不动，
  而不是把顶部条目钉在原地。换算关系为 `targetTop = offset_B(i) + r * stride_B - f`，
  与顶部锚定只差 `r * (stride_B - stride_A)`。
* **修复滚动补偿从未生效**：`Scrollable.maybeOf(context)` 在 `FolderZoomSliverBuilder` 的 context
  上恒为 `null`（它在 `CustomScrollView` 之上），导致中段 / 底部换档时纯跳变。
  现在优先取新增的可选参数 `controller`，未传时自动从渲染树里找到 `ScrollPosition`。
* **补齐底部边界**：贴底换档按两端内容总高之差换算目标滚动位置（`SliverPadding` 不会引入偏移）；
  过渡期的滚动残差回写给各档位层的视口顶部，可见性判断不再与屏幕打架（消除整屏空白帧）。
* **捏合跟手**：捏合开始时按双指中点重新取锚，并在手势期间驱动滚动。
* **测试**：新增 `test/zoom_anchor_test.dart`，覆盖顶部 / 中段 / 底部 × 两个方向的共同可见条目、
  贴底精度、空白帧与控制器自动发现。

## 0.0.1

* TODO: Describe initial release.
