## 未发布

* **支持"一个页面里多个缩放列表"**：一个 [FolderZoomSliverBuilder] 下可以挂多个网格
  （目录列表 → 固定高的介绍行 → 文件列表这类结构）。用
  `SliverAnimatedZoomGridDelegate(section: ...)` 声明身份、`ZoomItemScaffold(section: ...)`
  对上同一个人身份即可，滚动补偿会自动把两段一起算：
  * 求解从"本 sliver 局部坐标"改成**页面坐标**：
    `targetPixels = gapBefore + Σ上游各段高度 + 本段局部目标`。
    下游网格会随上游网格的高度变化整体平移，这段位移以前完全没被补偿，
    换档瞬间下面那个列表会被顶走一个 `ΔH`（实测 336px）。
  * 每段各自维护 `precede / 条目数 / 间距 / 冻结表`，不再互相覆盖（以前后布局的那个
    会盖掉前一个的视口状态，导致另一段整片错位）。
  * 单侧可见条目的淡入淡出按段各冻结一份：两段的条目索引都从 0 开始，共用一张表
    会让条目互相顶替。
  * 布局侧的 `_layerViewportTop` 改成按段取；`computeMaxScrollOffset` 按段回填条目数。
  * `section` 留空时行为与旧版**完全一致**（仍是单列表路径），现有 43 个测试全部保持通过。
* **修复多列表的三个连带问题**（都在"下游列表滚到中段后换档"时才暴露）：
  * **上游高度补偿整段丢失**：段的存活判定原来靠"同一个段在一轮布局里出现两次"来
    判轮次，可同一个 sliver 一帧里本来就可能被布局多次，于是还活着的段被误判成
    已移除，`gapBefore` 被重算成 `precede` 本身（实测 284 → 696），
    下游列表换档瞬间被顶走上游那一段的高度。改用 `SchedulerBinding.currentFrameTimeStamp`
    作为帧标识（与 build 次数无关，同帧内恒定），并留 2 帧宽限。
  * **反复换档一路漂移**：锚每次都按"焦点所在行的第一个条目"重新取，而同一个索引在
    6 列和 8 列下属于不同的行，一来一回净丢一行，几十次之后就滑到页面底部。
    现在锚条目会**粘住**上一次的索引（只要它仍与焦点同行），来回换档精确回到原位。
  * **下游列表淡入淡出消失**：冻结表里的"目标视口位置"也受上面那处污染影响，
    单侧可见的条目被判成"两侧都可见"，于是不淡入也不淡出、直接闪现。上游补偿恢复后
    判定跟着正确，条目恢复原地淡入淡出。
  * `gapBefore` 只在**稳态**（单层几何）刷新：过渡期各段高度是插值值，
    反推出来的既不是这一档也不是那一档的值。
  * `_resolveFocusY` 的"距顶一屏压焦点"改用**页面坐标**判断（扣掉第一个网格段之前的
    页头）；用段局部偏移会让第二段在页面中段时被误判成"贴着顶部"，
    焦点从视口中心被压到本段第一行。
* **测试**：`test/zoom_multi_section_test.dart` 扩到 7 例，新增"第二个列表中部反复换档
  回到原位（3 个来回）"与"单侧可见条目真的在视口里逐帧淡出"。
* **示例**：新增 `example/lib/multi_list_page.dart`（一页两个列表 + 固定高介绍行）。
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
