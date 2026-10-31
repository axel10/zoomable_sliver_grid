import 'package:flutter/material.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

import 'multi_list_page.dart';

void main() {
  runApp(const ZoomableGridExampleApp());
}

class DemoItem {
  final int id;
  final String title;
  final String subtitle;
  final String info;
  final Color color;
  final IconData icon;

  const DemoItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.info,
    required this.color,
    required this.icon,
  });
}

class ZoomableGridExampleApp extends StatelessWidget {
  const ZoomableGridExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zoomable Sliver Grid Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.indigoAccent,
      ),
      home: const DemoHomePage(),
    );
  }
}

class DemoHomePage extends StatefulWidget {
  const DemoHomePage({super.key});

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage> {
  double _zoomScale = kFolderZoomTierStandardList;
  final Set<int> _selectedIds = <int>{};
  bool _isSelectionMode = false;

  late final List<DemoItem> _items = List.generate(120, (index) {
    final colors = [
      Colors.pinkAccent,
      Colors.deepPurpleAccent,
      Colors.indigoAccent,
      Colors.blueAccent,
      Colors.teal,
      Colors.green,
      Colors.amber,
      Colors.orangeAccent,
      Colors.deepOrange,
      Colors.cyan,
    ];
    final icons = [
      Icons.music_note_rounded,
      Icons.album_rounded,
      Icons.audiotrack_rounded,
      Icons.graphic_eq_rounded,
      Icons.mic_external_on_rounded,
      Icons.radio_rounded,
      Icons.headset_rounded,
      Icons.queue_music_rounded,
    ];
    return DemoItem(
      id: index,
      title: 'Track ${index + 1} - Acoustic Echo',
      subtitle: 'Artist ${(index % 12) + 1} • Studio Album ${(index % 5) + 1}',
      info: '${(3 + (index % 4))}:${((index * 13) % 60).toString().padLeft(2, '0')} | FLAC 24-bit',
      color: colors[index % colors.length],
      icon: icons[index % icons.length],
    );
  });

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
        _isSelectionMode = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zoomable Sliver Grid'),
        actions: [
          IconButton(
            icon: const Icon(Icons.view_agenda_rounded),
            tooltip: '一页两个列表',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MultiListPage(),
                ),
              );
            },
          ),
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Clear Selection',
              onPressed: () {
                setState(() {
                  _selectedIds.clear();
                  _isSelectionMode = false;
                });
              },
            ),
          ZoomButton(
            zoomScale: _zoomScale,
            onZoomScaleChanged: (scale) {
              setState(() => _zoomScale = scale);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return ZoomGestureLayer(
            zoomScale: _zoomScale,
            onZoomScaleChanged: (scale) {
              setState(() => _zoomScale = scale);
            },
            child: FolderZoomSliverBuilder(
              zoomScale: _zoomScale,
              width: constraints.maxWidth,
              builder: (context, metrics) {
                return CustomScrollView(
                  slivers: [
                    // 演示"缩放列表上方还有别的组件"：列表起始边不在视口顶端时，
                    // 换档 / 捏合仍要按焦点补偿滚动（见 README「Grid below other slivers」）。
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Container(
                          height: 160,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF3F51B5), Color(0xFF7C4DFF)],
                            ),
                          ),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              const Icon(Icons.graphic_eq_rounded, size: 32),
                              const SizedBox(height: 12),
                              Text(
                                'Recently played',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '上方这块 header 会随列表一起滚走；'
                                '它还在屏幕内时换档也应该跟手',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: folderContentHorizontalPadding(
                          isPortrait: metrics.isPortrait,
                          gridMorph: metrics.gridMorph,
                        ),
                        vertical: 16.0,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: SliverAnimatedZoomGridDelegate(
                          metrics: metrics,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = _items[index];
                            final isSelected = _selectedIds.contains(item.id);

                            return ZoomItemScaffold(
                              metrics: metrics,
                              isSelected: isSelected,
                              isSelectionMode: _isSelectionMode,
                              onTap: () {
                                if (_isSelectionMode) {
                                  _toggleSelection(item.id);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Tapped ${item.title}'),
                                      duration: const Duration(milliseconds: 600),
                                    ),
                                  );
                                }
                              },
                              onLongPress: () {
                                _toggleSelection(item.id);
                              },
                              cover: ZoomItemCover(
                                metrics: metrics,
                                isSelected: isSelected,
                                isSelectionMode: _isSelectionMode,
                                onToggleSelect: () => _toggleSelection(item.id),
                                onPlay: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Playing ${item.title}'),
                                      duration: const Duration(milliseconds: 600),
                                    ),
                                  );
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        item.color.withValues(alpha: 0.85),
                                        item.color.withValues(alpha: 0.40),
                                      ],
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      item.icon,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                  ),
                                ),
                              ),
                              titleText: item.title,
                              subtitleText: item.subtitle,
                              infoText: item.info,
                              trailing: IconButton(
                                icon: const Icon(Icons.more_vert_rounded, size: 20),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('More for ${item.title}'),
                                      duration: const Duration(milliseconds: 600),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                          childCount: _items.length,
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
