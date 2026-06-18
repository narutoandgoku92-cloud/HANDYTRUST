import 'package:flutter/material.dart';

/// Full-screen, pinch-to-zoom portfolio image viewer. Shared by
/// ArtisanProfileScreen and PortfolioManagerScreen so the gallery UX isn't
/// duplicated across both call sites.
Future<void> showPortfolioViewer(
  BuildContext context, {
  required List<String> imageUrls,
  required int initialIndex,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, _, _) => _PortfolioViewer(
        imageUrls: imageUrls,
        initialIndex: initialIndex,
      ),
    ),
  );
}

class _PortfolioViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const _PortfolioViewer({
    required this.imageUrls,
    required this.initialIndex,
  });

  @override
  State<_PortfolioViewer> createState() => _PortfolioViewerState();
}

class _PortfolioViewerState extends State<_PortfolioViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.imageUrls.length,
        itemBuilder: (ctx, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.network(
              widget.imageUrls[i],
              fit: BoxFit.contain,
              errorBuilder: (_, err, stack) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
