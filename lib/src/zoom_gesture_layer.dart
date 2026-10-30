import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'zoom_layout_utils.dart';
import 'zoom_pinch.dart';

/// 两次滚轮事件之间静默多久，就算「新的一次滚动」。
const Duration kFolderZoomWheelGestureGap = Duration(milliseconds: 50);

/// 捏合比例超过这个倍数（或它的倒数）才算「有明确的放大/缩小意图」。
const double kFolderZoomPinchStepRatio = 1.08;

/// 给「按档位缩放条目」的滚动区挂上跨平台手势调节入口：
///
/// - 键鼠：`Ctrl` + 滚轮（macOS 上 `⌘` + 滚轮同样有效），向上滚放大、向下滚缩小，
///   一次滚动只走一档；
/// - 触控板：双指捏合实时跟手；
/// - 触屏：双指捏合实时跟手。
class ZoomGestureLayer extends StatefulWidget {
  const ZoomGestureLayer({
    super.key,
    required this.zoomScale,
    required this.onZoomScaleChanged,
    required this.child,
    this.minScale = kFolderZoomTierMinimalList,
    this.maxScale = kFolderZoomTierLargeGrid,
    this.enableHaptics = true,
  });

  final double zoomScale;
  final ValueChanged<double> onZoomScaleChanged;
  final Widget child;
  final double minScale;
  final double maxScale;
  final bool enableHaptics;

  @override
  State<ZoomGestureLayer> createState() => _ZoomGestureLayerState();
}

class _ZoomGestureLayerState extends State<ZoomGestureLayer>
    with TickerProviderStateMixin {
  late final FolderZoomPinchController _pinchController;

  @override
  void initState() {
    super.initState();
    _pinchController = FolderZoomPinchController(vsync: this);
  }

  @override
  void dispose() {
    _pinchController.dispose();
    super.dispose();
  }

  Duration? _lastWheelStamp;
  int _wheelBurstDirection = 0;
  bool _wheelBurstStepped = false;

  bool get _isZoomModifierPressed {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed) return true;
    return defaultTargetPlatform == TargetPlatform.macOS &&
        keyboard.isMetaPressed;
  }

  void _stepTier(int steps, {bool haptic = false}) {
    if (steps == 0) return;
    final current = widget.zoomScale;
    final stepped = stepFolderZoomScale(current, steps);
    final next = stepped.clamp(widget.minScale, widget.maxScale);
    if ((next - current).abs() < 1e-6) return;
    widget.onZoomScaleChanged(next);
    if (haptic && widget.enableHaptics) {
      HapticFeedback.selectionClick();
    }
  }

  void _commitPinchTier(double newScale) {
    final current = widget.zoomScale;
    final next = newScale.clamp(widget.minScale, widget.maxScale);
    if ((next - current).abs() < 1e-6) return;
    widget.onZoomScaleChanged(next);
    if (widget.enableHaptics) {
      HapticFeedback.selectionClick();
    }
  }

  void _startPinchGesture({Offset? focal}) {
    _pinchController.startPinch(
      widget.zoomScale,
      min: widget.minScale,
      max: widget.maxScale,
      focal: focal,
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_isZoomModifierPressed) return;

    final delta = event.scrollDelta;
    final double amount = delta.dy != 0 ? delta.dy : delta.dx;
    if (amount == 0) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent signal,
    ) {
      if (signal is PointerScrollEvent) {
        signal.respond(allowPlatformDefault: false);
      }
      _handleWheel(amount, event.timeStamp);
    });
  }

  void _handleWheel(double amount, Duration timeStamp) {
    final int direction = amount.isNegative ? 1 : -1;

    final lastStamp = _lastWheelStamp;
    _lastWheelStamp = timeStamp;

    final bool continuesBurst = lastStamp != null &&
        timeStamp >= lastStamp &&
        timeStamp - lastStamp < kFolderZoomWheelGestureGap &&
        direction == _wheelBurstDirection;

    if (!continuesBurst) {
      _wheelBurstDirection = direction;
      _wheelBurstStepped = false;
    }
    if (_wheelBurstStepped) return;

    _wheelBurstStepped = true;
    _stepTier(direction);
  }

  static const double _kPinchActivateRatio = 1e-3;

  void _pushPinchScale(double scale, {Offset? focal}) {
    if (_pinchController.isEnding) return;
    if (!_pinchController.isActive) {
      if ((scale - 1.0).abs() < _kPinchActivateRatio) return;
      _startPinchGesture(focal: focal);
    }
    _pinchController.updatePinch(
      scale: scale,
      focal: focal,
      onThresholdCrossed: () {
        if (widget.enableHaptics) {
          HapticFeedback.selectionClick();
        }
      },
    );
  }

  void _handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _pushPinchScale(event.scale, focal: event.position);
  }

  void _handlePanZoomEnd(PointerPanZoomEndEvent event) {
    if (!_pinchController.isActive || _pinchController.isEnding) return;
    _pinchController.endPinch(onCommit: _commitPinchTier);
  }

  final Map<int, Offset> _touchPointers = <int, Offset>{};
  double? _pinchBaseSpan;

  bool _isTouch(PointerEvent event) => event.kind == PointerDeviceKind.touch;

  void _handleTouchDown(PointerDownEvent event) {
    if (!_isTouch(event)) return;
    _touchPointers[event.pointer] = event.position;
    if (_touchPointers.length >= 2) {
      _pinchBaseSpan = _currentSpan();
    }
  }

  void _handleTouchMove(PointerMoveEvent event) {
    if (!_isTouch(event) || !_touchPointers.containsKey(event.pointer)) return;
    _touchPointers[event.pointer] = event.position;

    if (_pinchController.isEnding) return;

    final base = _pinchBaseSpan;
    if (base == null || base <= 0) return;
    final span = _currentSpan();
    if (span <= 0) return;

    _pushPinchScale(span / base, focal: _currentFocal());
  }

  /// 双指中点（全局坐标），作为捏合缩放时"手指下方内容不动"的焦点。
  Offset? _currentFocal() {
    if (_touchPointers.isEmpty) return null;
    var sum = Offset.zero;
    for (final point in _touchPointers.values) {
      sum += point;
    }
    return sum / _touchPointers.length.toDouble();
  }

  void _handleTouchUp(PointerEvent event) {
    if (!_isTouch(event)) return;
    if (_touchPointers.remove(event.pointer) == null) return;
    if (_touchPointers.length < 2) {
      _pinchBaseSpan = null;
      if (_pinchController.isActive && !_pinchController.isEnding) {
        _pinchController.endPinch(onCommit: _commitPinchTier);
      }
    }
  }

  double _currentSpan() {
    final count = _touchPointers.length;
    if (count < 2) return 0;
    if (count == 2) {
      final it = _touchPointers.values;
      return (it.first - it.last).distance;
    }
    double maxSpan = 0;
    final points = _touchPointers.values.toList(growable: false);
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final distance = (points[i] - points[j]).distance;
        if (distance > maxSpan) maxSpan = distance;
      }
    }
    return maxSpan;
  }

  @override
  Widget build(BuildContext context) {
    return FolderZoomPinchScope(
      notifier: _pinchController,
      child: RawGestureDetector(
        gestures: <Type, GestureRecognizerFactory>{
          _ZoomPinchGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<_ZoomPinchGestureRecognizer>(
                () => _ZoomPinchGestureRecognizer(debugOwner: this),
                (_ZoomPinchGestureRecognizer instance) {},
              ),
        },
        child: Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _handleTouchDown,
                onPointerMove: _handleTouchMove,
                onPointerUp: _handleTouchUp,
                onPointerCancel: _handleTouchUp,
                onPointerSignal: _handlePointerSignal,
                onPointerPanZoomUpdate: _handlePanZoomUpdate,
                onPointerPanZoomEnd: _handlePanZoomEnd,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomPinchGestureRecognizer extends ScaleGestureRecognizer {
  _ZoomPinchGestureRecognizer({super.debugOwner});

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) => false;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    return event.kind == PointerDeviceKind.touch && super.isPointerAllowed(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (event is PointerDownEvent && pointerCount >= 2) {
      resolve(GestureDisposition.accepted);
    }
  }
}
