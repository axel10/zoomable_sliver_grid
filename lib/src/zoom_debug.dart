import 'package:flutter/foundation.dart';

/// 是否输出档位过渡的调试日志。
///
/// 默认只在 debug 构建里打开，release 里完全静默。排查安卓真机上"换档时列表
/// 快速上下移动"这类问题时可临时打开；定位结束后把它改成 `false` 或删掉插桩。
bool folderZoomDebugLog = !kReleaseMode;

/// 统一的日志输出入口，按 `[zoom][channel]` 前缀分频道，方便在 logcat 里过滤。
void zoomLog(String channel, String Function() message) {
  if (!folderZoomDebugLog) return;
  debugPrint('[zoom][$channel] ${message()}');
}

/// 数字格式化：`null` 输出 `null`，其余保留 [digits] 位小数。
String zd(double? value, [int digits = 1]) =>
    value == null ? 'null' : value.toStringAsFixed(digits);

