## 未发布

* **修复「滚到列表底部后捏合换档，整片内容偏下」**：捏合路径曾按目标档位的
  `maxScrollOffsetFor()` 夹取目标滚动位置，那是 **sliver 坐标**（`内容总高 - 视口高`，
  不含外层 `SliverPadding`），而目标值是滚动像素——两者相差一个 `precede`
  （上方 header / padding 高度）加尾部 padding。于是只有贴底这一种情形会露馅：
  点击档位精确贴底，捏合却提前停下 `precede + 尾部 padding` 那么多，最后一行被切掉一截。
  header 越高偏得越多（实测无 header 32px、400px header 432px）。
  现在与点击路径一致**不按上界夹取**，越界交给本次布局的 `applyContentDimensions` 纠正。
* **测试**：新增 `test/zoom_bottom_pinch_matches_tap_test.dart`，在"无 header / 400px header"
  × 放大 / 缩小 四种组合下比对两条路径的最终滚动像素与每一条的屏幕位置，要求逐条对齐。
  已验证修复前失败（少滚 32px / 432px）。

## 0.0.4

* **适配"缩放列表上方还有别的组件"**：调用方在列表上方放了 header / banner / `SliverAppBar`
  时，列表起始边不在视口顶端，此时 `SliverConstraints.scrollOffset` 会被 Flutter 钳在 0
  （`RenderViewportBase.layoutChildSequence`：`scrollOffset <= 0 ? 0 : scrollOffset`）。
  早期实现直接拿它当 `viewportTop`，于是把这种状态误判成"列表已贴顶"：
  换档 / 捏合**完全不补偿滚动**（日志里的 `skip: no scroll delta`），内容只在原地往下长，
  焦点条目被甩出屏外。
  现在按 `viewportTop = scrollOffset - max(0, viewportMainAxisExtent - remainingPaintExtent)`
  还原真实坐标系（起始边在视口顶端之下时是负值），改动连带：
  * `viewportHeight` 恢复成**视口高度**，不再是 `remainingPaintExtent`（被 header 吃掉一截，
    实测 584 vs 800）；`maxScrollOffsetFor` 与 `_isOnScreen` 的可见性判定随之对齐。
  * 贴顶判据改成"页面还有没有向上余量"（`pixels == 0`），而不是 `viewportTop <= 0.5`；
    顶对齐的目标改成"把起始边钉在当前位置"，不再写死 `0`（那会让贴顶换档多滚一整个 header）。
  * `_resolveFocusY` 的"距顶一屏压焦点"只在**内容起始边已被推到视口顶端之上**时生效；
    起始边在视口顶端之下时焦点正常取视口中心，交给"焦点落到内容之外才退化成顶对齐"兜底。
  * `viewportTopForLayer` 的夹取下界从 `0` 改成 `-precede`（页面滚到 0 时的坐标）。
* **测试**：新增 `test/zoom_header_offset_test.dart`，覆盖"可滚走 header / 吸顶 header"两种布局
  × 页面顶端 / 中段 / 贴底 × 点击换档 / 双指捏合，断言换档必须补偿滚动、焦点内容留在焦点处、
  贴底精确贴住 `maxScrollExtent`。已验证这些用例在修复前失败（pixels 原地不动）。

## 0.0.3

* **修复触底换档"从下往上弹一下"**：过渡期的条目几何曾按"该条目在某一层视口内是否可见"
  **逐帧**分支（两层都可见走加权混合，只有一层可见就锁死到那一层的屏幕位置）。可见性是布尔量，
  而过渡期滚动位置要在几千像素上平移，条目会反复翻转可见性，每翻一次位置就在"混合值"和
  "层锁定值"之间瞬移一次。
  现在分类仍然保留（两侧档位都可见的才做位移动画，只在一侧可见的原地淡入淡出），但**在过渡
  开始时一次性冻结**（`FolderZoomItemPinning`）：判定结果和锁定位置都不再随帧变化，翻转成因
  消失；`resolveItemTransition` 恢复 `isShared == false` 分支，配合 `kFolderZoomFadeScaleDelta`
  做不透明度 + 轻微缩放的原地进出。连点两档时旧表被带入新表，锁定条目沿用上一帧真实画出的
  位置，不会瞬移。
* **修复滚动补偿慢一帧**：`_onTick` 曾用上一帧的 `maxScrollExtent` 夹取插值位置。触底换档时
  内容每帧要长上千像素，夹取让滚动永远落后一帧，条目先被画低上千像素、下一帧再被拽回。
  现在不再按过期的最大偏移夹取，越界交给本次布局的 `applyContentDimensions` 纠正。
* **补齐过渡终帧**：`AnimationController` 在最后一个 tick 里先 `stop()` 再 `notifyListeners()`，
  原来靠 `isAnimating` 做闸门会丢掉最后一步补偿，实测触底会停在离底部十几像素处且残差随帧率变化。
  改为挂在 completed 状态上补最后一帧。
* **修复过渡中再次换档偏移被算高**：起点视口顶部取自上一次布局，起点像素取自当前时刻，
  两者差一整帧的滚动量。现在按"上次布局时的像素 → sliver 顶部"的固定差值把两者对齐到同一时刻
  （触底连点两档曾多算 290px，滚动越界后靠回弹模拟弹回）。
* **修复捏合换档时所有条目一起位移**：`build()` 的捏合分支没有把 `itemPinning` 传进
  `FolderZoomLayoutMetrics`，整段捏合退化成"所有条目按两端几何加权位移"，只在单侧可见的条目
  也跟着插值上下漂（点击档位面板换档走 `_applyTargets` 那条路，有 `buildPinning()`，所以是对的）。
  现在捏合按 `(起始档位, 目标档位)` 缓存一张冻结表，方向确定那一帧生成、中途反向时重算，
  与点击换档完全同一套"共同可见条目位移 / 单侧条目原地淡入淡出"的行为。
* **测试**：新增 `test/zoom_pinch_single_side_fade_test.dart`，用真实双指手势驱动
  `ZoomGestureLayer`，断言捏合过程中单侧可见条目屏幕位置不动、不透明度在变，共同可见条目仍在位移。
* **测试**：新增 `test/zoom_transition_motion_test.dart`，断言过渡期间每个条目的屏幕位置**单调**变化
  （不允许中途折返），覆盖竖屏 / 横屏 / 触底放大 / 触底缩小 / 中段 / 连点两档；
  新增 `test/zoom_single_side_fade_test.dart`，断言单侧可见条目整段过渡**原地不动**且透明度在变，
  同时两侧都可见的条目仍在位移，以及连点两档时锁定条目不跳帧。

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
