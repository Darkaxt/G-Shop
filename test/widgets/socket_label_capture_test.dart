import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/widgets/socket_media_renderer.dart';

// RenderObject.debugNeedsPaint always returns false in release builds.
// Retain the real viewport/layout/paint lifecycle while exercising that contract.
class _ReleaseBoundary extends RenderRepaintBoundary {
  @override
  bool get debugNeedsPaint => false;
}

class _Label extends SingleChildRenderObjectWidget {
  const _Label({super.key})
      : super(child: const ColoredBox(color: Color(0xff123456)));
  @override
  _ReleaseBoundary createRenderObject(BuildContext context) =>
      _ReleaseBoundary();
}

void main() {
  testWidgets('cached shelf label waits for actual painting before capture',
      (tester) async {
    final key = GlobalKey();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: ListView.builder(
            controller: scroll,
            cacheExtent: 2000,
            itemExtent: 300,
            itemCount: 8,
            itemBuilder: (_, index) =>
                index == 4 ? _Label(key: key) : const SizedBox())));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    expect(boundary.hasSize, true);
    expect(boundary.debugNeedsPaint, false);
    expect(boundary.layer, null);
    expect(SocketMediaRendererState.labelCaptureReady(boundary), false,
        reason: 'Laid-out cached tiles have no capture layer until visible');
    scroll.jumpTo(1100);
    await tester.pump();
    expect(boundary.layer, isNotNull);
    expect(SocketMediaRendererState.labelCaptureReady(boundary), true);
    final image = await tester.runAsync(() => boundary.toImage());
    expect(image!.width, greaterThan(0));
    image.dispose();
    await tester.pumpWidget(const SizedBox());
    expect(SocketMediaRendererState.labelCaptureReady(boundary), false,
        reason: 'A detached producer cannot be captured');
  });
}
