import 'package:flutter/material.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 拖拽排序验收页：网格 / 列表两种档位，单条拖拽与多选合集拖拽。
///
/// 操作方式：
/// - 长按任意条目进入多选（只选一条就是单条拖拽）；
/// - 拖条目**右上角的拖拽手柄**起拖，多条选中时会收拢成一个合集；
/// - 拖动过程中余下条目自动填补空位，并在指针位置避让出合集落点；
/// - 松手把合集一次性插入到落点。
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

  double _zoomScale = kFolderZoomTierSmallGrid;
  final Set<int> _selectedIds = <int>{};
  bool _selectionMode = false;
  bool _alwaysShowHandles = false;
  // 网格态合集是只避让 1 个格子，还是按被拖条数避让 N 个格子，交给实测对比。
  bool _useFullPlaceholder = false;

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
          ZoomButton(
            zoomScale: _zoomScale,
            onZoomScaleChanged: _setZoom,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
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
                          ? (_selectedIds.length > 1 ? _selectedIds.length : 1)
                          : 1,
                      onReorder: _handleReorder,
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
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '长按条目进入多选（选 1 条 = 单条拖拽，选多条 = 合集拖拽）；'
            '拖右上角手柄移动，松手插入。拖到上下边缘会自动滚动。',
            style: theme.textTheme.bodySmall,
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
