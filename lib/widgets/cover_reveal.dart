import 'dart:math' as math;
import 'package:flutter/material.dart';

/// One focus, one reveal. Only an already decoded image is admitted; this widget
/// never starts an image/HTTP load or replays after later artwork resolution.
class CoverReveal extends StatefulWidget {
  static const duration = Duration(milliseconds: 2400);
  final String identity;
  final ImageProvider? boxArt;
  final Widget media;
  final bool reducedMotion;
  const CoverReveal(
      {super.key,
      required this.identity,
      required this.media,
      this.boxArt,
      this.reducedMotion = false});
  @override
  State<CoverReveal> createState() => _CoverRevealState();
}

class _CoverRevealState extends State<CoverReveal>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _animation =
      AnimationController(vsync: this, duration: CoverReveal.duration);
  ImageInfo? _cover;
  bool _decided = false;
  bool get _reduce =>
      widget.reducedMotion || MediaQuery.disableAnimationsOf(context);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _choose();
  }

  @override
  void didUpdateWidget(CoverReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _animation.stop();
      _animation.reset();
      _cover?.dispose();
      _cover = null;
      _decided = false;
    }
    _choose();
  }

  void _choose() {
    if (_reduce || !TickerMode.valuesOf(context).enabled) {
      _animation.value = 1;
      _decided = true;
      return;
    }
    if (_decided) return;
    final provider = widget.boxArt;
    if (provider != null) {
      final config = createLocalImageConfiguration(context);
      // File/Memory/Resize/CachedNetwork providers return synchronous cache keys.
      // An asynchronous key cannot establish resolved artwork for this focus.
      provider.obtainKey(config).then((key) {
        if (_decided) return;
        final status = PaintingBinding.instance.imageCache.statusForKey(key);
        if (status.pending || (!status.live && !status.keepAlive)) return;
        final stream = provider.resolve(config);
        final listener = ImageStreamListener((image, synchronous) {
          if (synchronous && !_decided) _cover = image.clone();
        }, onError: (_, __) {});
        stream.addListener(listener);
        stream.removeListener(listener);
      }, onError: (_, __) {});
    }
    _decided = true;
    if (_cover != null) {
      _animation.forward();
    } else {
      _animation.value = 1;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _animation.value = 1;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    _cover?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final image = _cover?.image;
        final aspect = image == null ? 1.0 : image.width / image.height;
        final coverWidth =
            math.min(bounds.maxWidth * .9, bounds.maxHeight * .9 * aspect);
        final coverHeight = coverWidth / aspect;
        final initial = math.min(
            1.0,
            math.min(coverWidth * .8 / bounds.maxWidth,
                coverHeight * .8 / bounds.maxHeight));
        return ClipRect(
            child: AnimatedBuilder(
                animation: _animation,
                builder: (context, _) {
                  final reveal =
                      image != null && !_reduce && !_animation.isCompleted;
                  final t = const Interval(.25, 1, curve: Curves.easeInOut)
                      .transform(_animation.value);
                  final scale = reveal ? initial + (1 - initial) * t : 1.0;
                  final left = (bounds.maxWidth - coverWidth) / 2;
                  return Stack(fit: StackFit.expand, children: [
                    Transform.scale(
                        key: const ValueKey('cover-reveal-media'),
                        scale: scale,
                        child: widget.media),
                    if (reveal)
                      Positioned(
                          left: left - (left + coverWidth + 1) * t,
                          top: (bounds.maxHeight - coverHeight) / 2,
                          width: coverWidth,
                          height: coverHeight,
                          child: RawImage(
                              key: const ValueKey('cover-reveal-cover'),
                              image: image,
                              fit: BoxFit.contain)),
                  ]);
                }));
      });
}
