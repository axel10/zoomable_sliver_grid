import 'package:flutter/foundation.dart';

/// 是否输出档位过渡的调试日志。
///
/// 默认完全关闭，所有构建模式都静默。排查安卓真机上"换档时列表快速上下移动"
/// 这类问题时可临时改成 `true`（或在调试时用 `--dart-define` 之外的方式置位）；
/// 定位结束后记得改回 `false`。
bool folderZoomDebugLog = false;

/// 统一的日志输出入口，按 `[zoom][channel]` 前缀分频道，方便在 logcat 里过滤。
void zoomLog(String channel, String Function() message) {
  if (!folderZoomDebugLog) return;
  debugPrint('[zoom][$channel] ${message()}');
}

/// 数字格式化：`null` 输出 `null`，其余保留 [digits] 位小数。
String zd(double? value, [int digits = 1]) =>
    value == null ? 'null' : value.toStringAsFixed(digits);

/// 布局几何探针开关。
///
/// 排查「SliverGeometry is not valid / scrollExtent 为负」这类 sliver 几何问题时
/// 打开。输出按频道（`[zoomGeom] <频道> ...`）分别去重：同一状态每 60 次确认一条；
/// `layout` / `maxScroll` 两个高频频道另加 120ms 节流，换档动画期间也不会刷屏。
///
/// 定位结束后改回 `false`。
bool folderZoomGeometryProbe = true;

/// 高频探针频道的最小输出间隔。
const Duration kGeomProbeMinInterval = Duration(milliseconds: 120);

final Map<String, ({String signature, int repeat})> _geomProbeStates =
    <String, ({String signature, int repeat})>{};
DateTime? _geomProbeLastThrottledAt;

/// 按签名去重的几何探针输出：签名相同视为"还是同一个状态"。
///
/// [throttled] 为 `true` 时另加 [kGeomProbeMinInterval] 的全局间隔限制，用于
/// 每帧都会调用的高频位置（布局参数、内容总高）。
void zoomGeomProbe(
  String signature,
  String Function() message, {
  bool throttled = false,
}) {
  if (!folderZoomGeometryProbe) return;
  final int split = signature.indexOf('|');
  final String channel = split < 0 ? signature : signature.substring(0, split);

  final previous = _geomProbeStates[channel];
  if (previous != null && previous.signature == signature) {
    final int repeat = previous.repeat + 1;
    _geomProbeStates[channel] = (signature: signature, repeat: repeat);
    if (repeat % 60 != 0) return;
  } else {
    _geomProbeStates[channel] = (signature: signature, repeat: 0);
  }

  if (throttled) {
    final DateTime now = DateTime.now();
    final DateTime? last = _geomProbeLastThrottledAt;
    if (last != null && now.difference(last) < kGeomProbeMinInterval) return;
    _geomProbeLastThrottledAt = now;
  }

  // final int repeat = _geomProbeStates[channel]!.repeat;
  // debugPrint('[zoomGeom] ${message()}${repeat > 0 ? ' ×$repeat' : ''}');
}

