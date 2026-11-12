import 'package:flutter/material.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 一个页面里放**多段**参与缩放的网格（默认 4 段）：
/// 目录 → 收藏 → 一行固定高的介绍 → 文件列表 → 最近播放。
///
/// 所有网格共用同一个 [FolderZoomSliverBuilder]（列数 / 字号只取决于宽度和档位，
/// 天然一致），各自通过 `SliverAnimatedZoomGridDelegate.section` 声明身份。
/// 换档时滚动补偿按页面坐标统一结算：任意一段变高变矮，它下游的所有段都会一起
/// 平移，所以整页是一起动、一起停的，不会出现"上面动完下面才跳一下"。
///
/// 段数不限于两段 —— 段之间夹的固定高内容（段标题、介绍卡）多几层也没关系，
/// 那些高度会从 `precede` 里扣掉，只留下"不随档位变化"的部分。
class MultiListPage extends StatefulWidget {
  const MultiListPage({super.key});

  @override
  State<MultiListPage> createState() => _MultiListPageState();
}

class _MultiListPageState extends State<MultiListPage> {
  static const Object _folderSection = 'folders';
  static const Object _favoriteSection = 'favorites';
  static const Object _fileSection = 'files';
  static const Object _recentSection = 'recent';

  double _zoomScale = kFolderZoomTierStandardList;

  final List<_DemoItem> _folders = List.generate(12, (i) {
    return _DemoItem(
      title: '目录 ${i + 1}',
      subtitle: '${3 + i % 7} 个文件',
      info: '2026-10-${(i + 1).toString().padLeft(2, '0')}',
      color: const Color(0xFF7C4DFF),
      icon: Icons.folder_rounded,
    );
  });

  final List<_DemoItem> _favorites = List.generate(18, (i) {
    return _DemoItem(
      title: '收藏 ${i + 1}',
      subtitle: 'Artist ${i % 6 + 1}',
      info: '${2 + i % 4}:${((i * 11) % 60).toString().padLeft(2, '0')}',
      color: const Color(0xFFEC407A),
      icon: Icons.favorite_rounded,
    );
  });

  final List<_DemoItem> _files = List.generate(96, (i) {
    return _DemoItem(
      title: '录音 ${i + 1}.flac',
      subtitle: 'Artist ${i % 9 + 1}',
      info: '${(2 + i % 5)}:${((i * 7) % 60).toString().padLeft(2, '0')}',
      color: const Color(0xFF26A69A),
      icon: Icons.audiotrack_rounded,
    );
  });

  final List<_DemoItem> _recent = List.generate(24, (i) {
    return _DemoItem(
      title: '最近播放 ${i + 1}',
      subtitle: '昨天 ${8 + i % 12}:00',
      info: '${1 + i % 6}:${((i * 13) % 60).toString().padLeft(2, '0')}',
      color: const Color(0xFF42A5F5),
      icon: Icons.history_rounded,
    );
  });

  /// 段标题：固定高度、不参与缩放，夹在各段之间。
  Widget _sectionHeader(
    BuildContext context,
    String title, {
    required int count,
  }) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text('$count', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _section(
    FolderZoomLayoutMetrics metrics, {
    required Object section,
    required List<_DemoItem> items,
  }) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: folderContentHorizontalPadding(
          isPortrait: metrics.isPortrait,
          gridMorph: metrics.gridMorph,
        ),
        vertical: 8,
      ),
      sliver: SliverGrid(
        gridDelegate: SliverAnimatedZoomGridDelegate(
          metrics: metrics,
          section: section,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            return ZoomItemScaffold(
              metrics: metrics,
              // 与上面的 delegate 一致：两段的条目索引都从 0 开始，靠这个字段区分。
              section: section,
              titleText: item.title,
              subtitleText: item.subtitle,
              infoText: item.info,
              cover: ZoomItemCover(
                metrics: metrics,
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
                    child: Icon(item.icon, color: Colors.white, size: 30),
                  ),
                ),
              ),
            );
          },
          childCount: items.length,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('一页多段列表'),
        actions: [
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
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(
                          '这一页有 4 段网格（目录 / 收藏 / 录音文件 / 最近播放）都参与缩放，'
                          '中间的段标题和介绍卡高度固定；换档时它们之间的相对位置不该变',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                    _sectionHeader(context, '目录', count: _folders.length),
                    _section(
                      metrics,
                      section: _folderSection,
                      items: _folders,
                    ),
                    _sectionHeader(context, '收藏', count: _favorites.length),
                    _section(
                      metrics,
                      section: _favoriteSection,
                      items: _favorites,
                    ),
                    // 固定高的一行介绍：不属于任何一段，因此也不随档位变形。
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Container(
                          height: 108,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_open_rounded,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '共 ${_files.length} 个文件',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '这块高度是固定的，换档时上下四段'
                                      '必须一起被补偿',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _sectionHeader(context, '录音文件', count: _files.length),
                    _section(
                      metrics,
                      section: _fileSection,
                      items: _files,
                    ),
                    _sectionHeader(context, '最近播放', count: _recent.length),
                    _section(
                      metrics,
                      section: _recentSection,
                      items: _recent,
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
}

/// 示例用的最小数据模型。
class _DemoItem {
  const _DemoItem({
    required this.title,
    required this.subtitle,
    required this.info,
    required this.color,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String info;
  final Color color;
  final IconData icon;
}
