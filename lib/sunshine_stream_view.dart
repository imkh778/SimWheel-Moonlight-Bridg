import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'sunshine_settings.dart';
import 'sunshine_service.dart';

class SunshineStreamController extends ChangeNotifier {
  SunshineStreamController({required double initialOpacity})
    : _opacity = initialOpacity;

  double _opacity;
  bool _isStreaming = false;
  bool _showControls = false;
  String _statusText = 'Connecting to Sunshine...';
  Future<void> Function()? _reconnect;

  double get opacity => _opacity;
  bool get isStreaming => _isStreaming;
  bool get showControls => _showControls;
  String get statusText => _statusText;

  void updateStream({required bool isStreaming, String? statusText}) {
    _isStreaming = isStreaming;
    if (statusText != null) _statusText = statusText;
    notifyListeners();
  }

  Future<void> setOpacity(double value) async {
    _opacity = value;
    notifyListeners();
    await CacheService().setSunshineOpacity(value);
  }

  void toggleControls() {
    _showControls = !_showControls;
    notifyListeners();
  }

  void closeControls() {
    _showControls = false;
    notifyListeners();
  }

  void setReconnectHandler(Future<void> Function()? reconnect) {
    _reconnect = reconnect;
  }

  Future<void> reconnect() async {
    await _reconnect?.call();
  }
}

/// Widget responsible for displaying the Sunshine PC screen stream layer
/// and on-screen HUD overlay controls.
class SunshineStreamView extends StatefulWidget {
  final SunshineStreamController controller;
  final VoidCallback? onClose;
  final ValueChanged<Offset>? onMouseMove;
  final VoidCallback? onMouseTap;

  const SunshineStreamView({
    super.key,
    required this.controller,
    this.onClose,
    this.onMouseMove,
    this.onMouseTap,
  });

  @override
  State<SunshineStreamView> createState() => _SunshineStreamViewState();
}

class _SunshineStreamViewState extends State<SunshineStreamView> {
  static const MethodChannel _streamChannel = MethodChannel(
    'simwheel/moonlight',
  );
  static const EventChannel _streamEvents = EventChannel(
    'simwheel/moonlight_events',
  );
  bool _isStreaming = false;
  bool _isLoading = true;
  bool _hasNativeSurface = false;
  int? _textureId;
  String _statusText = 'Connecting to Sunshine...';
  String? _hostname;
  Timer? _statusTimer;
  StreamSubscription<dynamic>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    widget.controller.setReconnectHandler(_reconnect);
    if (defaultTargetPlatform == TargetPlatform.android) {
      _streamSubscription = _streamEvents.receiveBroadcastStream().listen(
        _handleStreamEvent,
        onError: (Object error) => _handleStreamError(error),
      );
    }
    _initializeStream();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _streamSubscription?.cancel();
    widget.controller.setReconnectHandler(null);
    if (_textureId != null) unawaited(_releaseStreamTexture());
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SunshineStreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.setReconnectHandler(null);
      widget.controller.setReconnectHandler(_reconnect);
    }
  }

  void _handleStreamEvent(dynamic event) {
    if (!mounted || event is! Map) return;
    final state = event['state']?.toString();
    final message = event['message']?.toString() ?? '';
    setState(() {
      if (message.isNotEmpty) _statusText = message;
      if (state == 'connected') {
        _isLoading = false;
        _isStreaming = true;
        _hasNativeSurface = true;
      } else if (state == 'error' || state == 'disconnected') {
        _isLoading = false;
        _isStreaming = false;
        _hasNativeSurface = false;
      }
    });
    widget.controller.updateStream(
      isStreaming: _isStreaming,
      statusText: message.isNotEmpty ? message : null,
    );
    if ((state == 'error' || state == 'disconnected') && _textureId != null) {
      unawaited(_releaseStreamTexture());
    }
  }

  void _handleStreamError(Object error) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _isStreaming = false;
      _hasNativeSurface = false;
      _statusText = 'Android video receiver error: $error';
    });
    widget.controller.updateStream(isStreaming: false, statusText: _statusText);
  }

  Future<void> _initializeStream() async {
    if (!mounted) return;
    if (_textureId != null) await _releaseStreamTexture();
    setState(() {
      _isLoading = true;
      _isStreaming = false;
      _hasNativeSurface = false;
      _statusText = 'Connecting to Sunshine...';
    });
    widget.controller.updateStream(isStreaming: false, statusText: _statusText);

    try {
      if (defaultTargetPlatform != TargetPlatform.android) {
        throw UnsupportedError(
          'The Sunshine video receiver currently supports Android.',
        );
      }
      final session = await SunshineService().startStreamSession();
      if (!mounted) return;
      final textureId = await _streamChannel.invokeMethod<int>('createTexture');
      if (!mounted) {
        await _streamChannel.invokeMethod<void>('releaseTexture');
        return;
      }
      if (textureId == null)
        throw StateError('Could not create the Android video surface.');
      setState(() {
        _hostname = session.host;
        _statusText = 'Starting Moonlight stream on ${session.host}...';
        _hasNativeSurface = true;
        _textureId = textureId;
      });
      widget.controller.updateStream(
        isStreaming: false,
        statusText: _statusText,
      );
      await _streamChannel.invokeMethod<bool>(
        'startStream',
        session.toPlatformMap(),
      );
    } catch (error) {
      if (!mounted) return;
      await _releaseStreamTexture();
      setState(() {
        _isLoading = false;
        _isStreaming = false;
        _hasNativeSurface = false;
        _statusText = error.toString().replaceFirst('Bad state: ', '');
      });
      widget.controller.updateStream(
        isStreaming: false,
        statusText: _statusText,
      );
    }
  }

  Future<void> _reconnect() async {
    await _releaseStreamTexture();
    if (!mounted) return;
    await _initializeStream();
  }

  Future<void> _releaseStreamTexture() async {
    if (_textureId == null) return;
    try {
      await _streamChannel.invokeMethod<void>('releaseTexture');
    } catch (_) {
      await _streamChannel.invokeMethod<void>('stopStream');
    }
    if (mounted) {
      setState(() {
        _textureId = null;
        _hasNativeSurface = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Opacity(
        opacity: widget.controller.opacity.clamp(0.1, 1.0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: const Color(0xFF0D1117),
              child: _buildStreamContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamContent() {
    if (_hasNativeSurface) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Texture(textureId: _textureId!),
          if (!_isStreaming)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.blueAccent),
                  const SizedBox(height: 14),
                  Text(
                    _statusText,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(Colors.blueAccent),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _statusText,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (!_isStreaming) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.symmetric(horizontal: 40),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.desktop_windows_outlined,
                size: 48,
                color: Colors.white38,
              ),
              const SizedBox(height: 12),
              Text(
                _hostname != null
                    ? "Sunshine: $_hostname"
                    : "Sunshine Screen Mirror",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _reconnect,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text("Retry Connection"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Active streaming surface:
    // When the native Moonlight video pipeline delivers frames, this renders the video surface.
    // For now it displays the active stream viewport HUD with live stream indicators.
    return Stack(
      children: [
        Center(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  Colors.blueAccent.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
                radius: 0.8,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tv_rounded,
                    size: 64,
                    color: Colors.blueAccent.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "PC VIDEO STREAM",
                    style: TextStyle(
                      color: Colors.blueAccent.withValues(alpha: 0.4),
                      letterSpacing: 3,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${_hostname ?? 'PC'} • ${CacheService().getSunshineResolution()} • ${CacheService().getSunshineFps()} FPS",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SunshineStreamControls extends StatelessWidget {
  final SunshineStreamController controller;

  const SunshineStreamControls({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Stack(
        children: [
          Positioned(
            top: 10,
            right: 60,
            child: SafeArea(
              child: Stack(
                children: [
                  IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.fromLTRB(10, 4, 32, 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: controller.isStreaming
                              ? Colors.greenAccent.withValues(alpha: 0.5)
                              : Colors.blueAccent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: controller.isStreaming
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            controller.isStreaming ? 'PC Screen' : 'Sunshine',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 6,
                    child: GestureDetector(
                      onTap: controller.toggleControls,
                      child: Icon(
                        controller.showControls
                            ? Icons.expand_less
                            : Icons.tune,
                        size: 16,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (controller.showControls)
            Positioned(
              top: 45,
              right: 60,
              child: SafeArea(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 260,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.blueAccent.withValues(alpha: 0.4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 15,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Screen Display HUD',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white54,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: controller.closeControls,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          controller.statusText,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.opacity,
                              size: 14,
                              color: Colors.blueAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Opacity: ${(controller.opacity * 100).toInt()}%',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: controller.opacity,
                          min: 0.2,
                          max: 1.0,
                          divisions: 8,
                          activeColor: Colors.blueAccent,
                          inactiveColor: Colors.white24,
                          onChanged: (value) =>
                              unawaited(controller.setOpacity(value)),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: controller.reconnect,
                              icon: const Icon(
                                Icons.refresh,
                                size: 14,
                                color: Colors.blueAccent,
                              ),
                              label: const Text(
                                'Reconnect',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blueAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
