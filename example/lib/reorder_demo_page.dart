import 'package:flutter/material.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 拖拽排序验收页：网格 / 列表两种档位，支持非多选鼠标直接拖拽与多选手柄集合拖拽。
///
/// 操作方式：
/// - 【非多选状态】：直接鼠标按住条目拖拽。在列表内移动显示高亮插入指示线，松手完成排序；
///   拖到右侧「模拟队列抽屉」松手，可直接将条目加入队列。
/// - 【多选状态】：长按条目进入多选，拖条目**右上角的拖拽手柄**起拖，多条选中时收拢成合集避让；
///   松手把合集一次性插入到落点。
class ReorderDemoPage extends StatefulWidget {
  const ReorderDemoPage({super.key});

  @override
  State<ReorderDemoPage> createState() => _ReorderDemoPageState();
}

class _ReorderDemoItem {
  const _ReorderDemoItem(this.id, this.color, this.icon);

  final int id;
  final Color color;
  final IconData icon;
}

class _ReorderDemoPageState extends State<ReorderDemoPage> {
  static const int _itemCount = 36;
  static const List<Color> _colors = <Color>[
    Colors.pinkAccent,
    Colors.deepPurpleAccent,
    Colors.indigoAccent,
    Colors.blueAccent,
    Colors.teal,
    Colors.green,
    Colors.amber,
    Colors.orangeAccent,
    Colors.deepOrangeAccent,
    Colors.cyan,
  ];
  static const List<IconData> _icons = <IconData>[
    Icons.music_note_rounded,
    Icons.album_rounded,
    Icons.audiotrack_rounded,
    Icons.graphic_eq_rounded,
    Icons.mic_external_on_rounded,
    Icons.radio_rounded,
    Icons.headset_rounded,
    Icons.queue_music_rounded,
  ];

  final ZoomReorderController _reorderController = ZoomReorderController();
  late List<_ReorderDemoItem> _items = List<_ReorderDemoItem>.generate(
    _itemCount,
    (index) => _ReorderDemoItem(
      index,
      _colors[index % _colors.length],
      _icons[index % _icons.length],
    ),
  );

  final List<String> _mockQueue = <String>[];
  bool _isQueueHovered = false;
  bool _showQueueDrawer = true;

  double _zoomScale = kFolderZoomTierSmallGrid;
  final Set<int> _selectedIds = <int>{};
  bool _selectionMode = false;
  bool _alwaysShowHandles = false;
  // 网格态合集是只避让 1 个格子，还是按被拖条数避让 N 个格子，交给实测对比。
  bool _useFullPlaceholder = false;

  // 异步重排演示配置
  bool _enableAsyncMode = true;
  int _mockNetworkDelayMs = 800;
  bool _simulateNetworkError = false;
  List<_ReorderDemoItem>? _previousItemsSnapshot;

  Set<int> get _selectedIndices {
    if (_selectedIds.isEmpty) return const <int>{};
    return <int>{
      for (var i = 0; i < _items.length; i++)
        if (_selectedIds.contains(_items[i].id)) i,
    };
  }

  void _setZoom(double value) {
    // 拖拽期间几何正在被重映射，换档会让槽位公式失效。
    if (_reorderController.isDragging) return;
    setState(() => _zoomScale = value);
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      _selectionMode = _selectedIds.isNotEmpty;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
  }

  void _handleReorder(Set<int> draggedIndices, int insertIndex) {
    setState(() {
      _items = ZoomReorderController.applyReorder(
        _items,
        draggedIndices,
        insertIndex,
      );
    });
  }

  Future<bool> _handleReorderAsync(
    Set<int> draggedIndices,
    int insertIndex,
  ) async {
    // 1. 备份快照供失败回滚
    _previousItemsSnapshot = List<_ReorderDemoItem>.from(_items);

    // 2. 乐观更新（Optimistic Update）
    setState(() {
      _items = ZoomReorderController.applyReorder(
        _items,
        draggedIndices,
        insertIndex,
      );
    });

    // 3. 模拟异步网络保存耗时
    if (_mockNetworkDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: _mockNetworkDelayMs));
    }

    // 4. 模拟失败分支
    if (_simulateNetworkError) {
      return false;
    }

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('云端保存成功！'),
          duration: Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return true;
  }

  void _handleReorderError(Object error, StackTrace stackTrace) {
    // 失败回滚至拖拽前的数据快照
    if (_previousItemsSnapshot != null) {
      setState(() {
        _items = _previousItemsSnapshot!;
        _previousItemsSnapshot = null;
      });
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: const Text('网络请求失败：已回滚至原有顺序！'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _reorderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('拖拽排序 demo'),
        actions: <Widget>[
          if (_selectionMode)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: '清除选择',
              onPressed: _clearSelection,
            ),
          IconButton(
            icon: Icon(
              _showQueueDrawer
                  ? Icons.view_sidebar_rounded
                  : Icons.view_sidebar_outlined,
            ),
            tooltip: _showQueueDrawer ? '隐藏队列面板' : '展开队列面板',
            onPressed: () => setState(() => _showQueueDrawer = !_showQueueDrawer),
          ),
          ZoomButton(
            zoomScale: _zoomScale,
            onZoomScaleChanged: _setZoom,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: <Widget>[
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ZoomGestureLayer(
                  zoomScale: _zoomScale,
                  onZoomScaleChanged: _setZoom,
                  reorderActive: _reorderController.reorderActive,
                  child: FolderZoomSliverBuilder(
                    zoomScale: _zoomScale,
                    width: constraints.maxWidth,
                    builder: (context, metrics) {
                      return CustomScrollView(
                        slivers: <Widget>[
                          SliverToBoxAdapter(child: _buildControlPanel(metrics)),
                          ZoomReorderableSliverGrid(
                            metrics: metrics,
                            width: constraints.maxWidth,
                            itemCount: _items.length,
                            itemKeyBuilder: (index) =>
                                ValueKey<int>(_items[index].id),
                            controller: _reorderController,
                            selectedIndices: _selectedIndices,
                            showHandles: _selectionMode || _alwaysShowHandles,
                            placeholderCount: _useFullPlaceholder
                                ? (_selectedIds.length > 1
                                    ? _selectedIds.length
                                    : 1)
                                : 1,
                            onReorder:
                                _enableAsyncMode ? null : _handleReorder,
                            onReorderAsync:
                                _enableAsyncMode ? _handleReorderAsync : null,
                            onReorderError:
                                _enableAsyncMode ? _handleReorderError : null,
                            itemDragItemBuilder:
                                (index, selectedIndices, localData, [request]) {
                              final List<String> titles;
                              if (selectedIndices.length > 1) {
                                titles = selectedIndices
                                    .where((i) => i >= 0 && i < _items.length)
                                    .map((i) => 'Track ${_items[i].id + 1}')
                                    .toList();
                              } else {
                                final item = _items[index];
                                titles = ['Track ${item.id + 1}'];
                              }

                              final dragItem = DragItem(
                                localData: {
                                  ...localData,
                                  'title': titles.first,
                                  'titles': titles,
                                },
                              );
                              dragItem.add(
                                Formats.plainText(titles.join('\n')),
                              );
                              return dragItem;
                            },
                            itemBuilder: (context, index) =>
                                _buildItem(context, metrics, index),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 32)),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
          if (_showQueueDrawer) _buildMockQueuePanel(),
        ],
      ),
    );
  }

  Widget _buildMockQueuePanel() {
    final theme = Theme.of(context);
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: <Widget>[
                const Icon(Icons.queue_music_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  '播放队列抽屉',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (_mockQueue.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    tooltip: '清空',
                    onPressed: () => setState(() => _mockQueue.clear()),
                  ),
              ],
            ),
          ),
          Expanded(
            child: DropRegion(
              formats: Formats.standardFormats,
              hitTestBehavior: HitTestBehavior.opaque,
              onDropOver: (event) {
                if (!_isQueueHovered) {
                  setState(() => _isQueueHovered = true);
                }
                return DropOperation.copy;
              },
              onDropLeave: (_) {
                if (_isQueueHovered) {
                  setState(() => _isQueueHovered = false);
                }
              },
              onDropEnded: (_) {
                if (_isQueueHovered) {
                  setState(() => _isQueueHovered = false);
                }
              },
              onPerformDrop: (event) async {
                setState(() => _isQueueHovered = false);
                final item = event.session.items.firstOrNull;
                final List<String> addedTitles = [];
                if (item?.localData is Map) {
                  final map = item!.localData as Map;
                  if (map['titles'] is List) {
                    addedTitles.addAll((map['titles'] as List).cast<String>());
                  } else if (map['title'] != null) {
                    addedTitles.add(map['title'].toString());
                  }
                }
                if (addedTitles.isEmpty) {
                  addedTitles.add('未知条目');
                }
                setState(() {
                  _mockQueue.addAll(addedTitles);
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      addedTitles.length > 1
                          ? '已将 ${addedTitles.length} 个条目批量加入播放队列！'
                          : '已将 ${addedTitles.first} 加入播放队列！',
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isQueueHovered
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                      : theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isQueueHovered
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                    width: _isQueueHovered ? 2.0 : 1.0,
                  ),
                ),
                child: _mockQueue.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.drag_indicator_rounded,
                              size: 32,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '直接拖拽条目到这里\n即可添加至队列',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _mockQueue.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 12,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                            title: Text(
                              _mockQueue[index],
                              style: theme.textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(FolderZoomLayoutMetrics metrics) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '当前档位：${metrics.isGridTarget ? "网格" : "列表"}'
            '　已选 ${_selectedIds.length} 条',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              ActionChip(
                label: const Text('列表档'),
                onPressed: () => _setZoom(kFolderZoomTierStandardList),
              ),
              ActionChip(
                label: const Text('网格档'),
                onPressed: () => _setZoom(kFolderZoomTierSmallGrid),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('常显手柄'),
                  Switch(
                    value: _alwaysShowHandles,
                    onChanged: (value) =>
                        setState(() => _alwaysShowHandles = value),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('合集占 N 槽'),
                  Switch(
                    value: _useFullPlaceholder,
                    onChanged: (value) =>
                        setState(() => _useFullPlaceholder = value),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('异步云端同步'),
                  Switch(
                    value: _enableAsyncMode,
                    onChanged: (value) =>
                        setState(() => _enableAsyncMode = value),
                  ),
                ],
              ),
              if (_enableAsyncMode) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('模拟延迟 ${_mockNetworkDelayMs}ms'),
                    const SizedBox(width: 4),
                    DropdownButton<int>(
                      value: _mockNetworkDelayMs,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(value: 300, child: Text('300ms')),
                        DropdownMenuItem(value: 800, child: Text('800ms')),
                        DropdownMenuItem(value: 1500, child: Text('1.5s')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _mockNetworkDelayMs = v);
                      },
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '模拟失败回滚',
                      style: TextStyle(
                        color: _simulateNetworkError
                            ? theme.colorScheme.error
                            : null,
                      ),
                    ),
                    Switch(
                      value: _simulateNetworkError,
                      activeTrackColor: theme.colorScheme.error,
                      onChanged: (value) =>
                          setState(() => _simulateNetworkError = value),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<bool>(
            valueListenable: _reorderController.isAsyncReordering,
            builder: (context, isReordering, _) {
              if (!isReordering) return const SizedBox.shrink();
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '正在同步至云端...（已自动锁定再次拖拽）',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            '【非多选】直接鼠标拖拽条目：列表内显示高亮线排序，拖到右侧抽屉加入队列；\n'
            '【多选】长按进入多选，右上角手柄起拖合集，多选挤开逻辑不受影响。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    FolderZoomLayoutMetrics metrics,
    int index,
  ) {
    final item = _items[index];
    final isSelected = _selectedIds.contains(item.id);
    return ZoomItemScaffold(
      // Stack 布局里没有 SliverMultiBoxAdaptorParentData，必须显式给索引，
      // 否则过渡分类会退化成 null。
      index: index,
      metrics: metrics,
      isSelected: isSelected,
      isSelectionMode: _selectionMode,
      onTap: () {
        if (_selectionMode) {
          _toggleSelection(item.id);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('点击了 #${item.id + 1}（长按进入多选）'),
              duration: const Duration(milliseconds: 600),
            ),
          );
        }
      },
      onLongPress: () => _toggleSelection(item.id),
      cover: ZoomItemCover(
        metrics: metrics,
        isSelected: isSelected,
        isSelectionMode: _selectionMode,
        onToggleSelect: () => _toggleSelection(item.id),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                item.color.withValues(alpha: 0.9),
                item.color.withValues(alpha: 0.45),
              ],
            ),
          ),
          child: Center(
            child: Icon(item.icon, color: Colors.white, size: 30),
          ),
        ),
      ),
      titleText: 'Track ${item.id + 1} - Acoustic Echo',
      subtitleText: 'Artist ${(item.id % 12) + 1} · Album ${(item.id % 5) + 1}',
      infoText: '#${item.id + 1} · ${(3 + item.id % 4)}:${((item.id * 13) % 60).toString().padLeft(2, '0')}',
      trailing: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
