import 'dart:math' as math;
import 'package:flutter/material.dart';

/// One focus, one reveal: a decoded real cover waits for selected-media readiness.
class CoverReveal extends StatefulWidget {
  static const duration = Duration(milliseconds: 1500);
  final String identity;
  final ImageProvider? boxArt;
  final Widget media;
  final bool reducedMotion;
  final bool mediaReady;
  final VoidCallback? onReady;
  const CoverReveal(
      {super.key,
      required this.identity,
      required this.media,
      this.boxArt,
      this.reducedMotion = false,
      this.mediaReady = true,
      this.onReady});
  @override
  State<CoverReveal> createState() => _CoverRevealState();
}

class _CoverRevealState extends State<CoverReveal>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _animation =
      AnimationController(vsync: this, duration: CoverReveal.duration);
  ImageInfo? _cover;
  bool _decided = false;
  ImageProvider? _requested;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  int _generation = 0;
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
      _cancelImage();
      _requested = null;
    }
    _choose();
  }

  void _choose() {
    if (_reduce || !TickerMode.valuesOf(context).enabled) {
      _cancelImage();
      _animation.value = 1;
      _decided = true;
      return;
    }
    if (_decided) return;
    if (_cover != null) {
      if (widget.mediaReady) {
        _decided = true;
        _animation.forward(from: 0);
        final generation = _generation;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _generation) widget.onReady?.call();
        });
      }
      return;
    }
    final provider = widget.boxArt;
    if (provider == null || provider == _requested) return;
    _cancelImage();
    _requested = provider;
    final generation = _generation;
    _stream = provider.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((image, synchronous) {
      if (!mounted || generation != _generation || _decided) return;
      void resolved() {
        _cover = image.clone();
        _cancelImage();
        _choose();
      }

      if (synchronous) {
        resolved();
      } else {
        setState(resolved);
      }
    }, onError: (_, __) {
      if (generation == _generation) _cancelImage();
    });
    _stream!.addListener(_listener!);
  }

  void _cancelImage() {
    _generation++;
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _decided = true;
      _cancelImage();
      _animation.value = 1;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    _cancelImage();
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
                  final t = Curves.easeInOut.transform(_animation.value);
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
