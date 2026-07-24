import 'package:flutter/material.dart';

/// Wraps [child] (typically a small thumbnail) so that hovering over it with
/// a mouse — desktop/web only, touch devices never fire onEnter/onExit —
/// shows a larger preview of [imageUrl] floating next to it.
///
/// The popup flips to whichever side/edge of the screen has room and shrinks
/// to fit rather than overflowing, since thumbnails can sit anywhere in the
/// layout (left edge of a list card, right column of a two-up detail row…).
class HoverImagePreview extends StatefulWidget {
  final String imageUrl;
  final Widget child;
  final double previewSize;
  final BorderRadius borderRadius;

  const HoverImagePreview({
    super.key,
    required this.imageUrl,
    required this.child,
    this.previewSize = 220,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  @override
  State<HoverImagePreview> createState() => _HoverImagePreviewState();
}

class _HoverImagePreviewState extends State<HoverImagePreview> {
  static const _margin = 16.0;
  static const _gap = 10.0;

  final _link = LayerLink();
  OverlayEntry? _entry;

  void _show() {
    _remove();
    final overlay = Overlay.maybeOf(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (overlay == null || renderBox == null || !renderBox.attached) return;

    final screenSize = MediaQuery.sizeOf(context);
    final targetTopLeft = renderBox.localToGlobal(Offset.zero);
    final targetSize = renderBox.size;

    final spaceRight  = screenSize.width  - (targetTopLeft.dx + targetSize.width) - _margin;
    final spaceLeft    = targetTopLeft.dx - _margin;
    final spaceBelow  = screenSize.height - targetTopLeft.dy - _margin;
    final spaceAbove  = targetTopLeft.dy - _margin;

    final showOnRight = spaceRight >= spaceLeft;
    final horizontalSpace = (showOnRight ? spaceRight : spaceLeft) - _gap;

    final showBelow = spaceBelow >= spaceAbove;
    final verticalSpace = showBelow ? spaceBelow : spaceAbove;

    // Shrink to whatever actually fits instead of overflowing the screen.
    final size = [widget.previewSize, horizontalSpace, verticalSpace, 120.0]
        .reduce((a, b) => a < b ? a : b);

    // Anchor to the target's top edge either way; only the follower's own
    // anchor flips (top → grows downward, bottom → grows upward) so it never
    // pushes past the top or bottom of the screen.
    final targetAnchor   = Alignment(showOnRight ? 1 : -1, -1);
    final followerAnchor = Alignment(showOnRight ? -1 : 1, showBelow ? -1 : 1);
    final offset = Offset(showOnRight ? _gap : -_gap, 0);

    _entry = OverlayEntry(
      builder: (context) => CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: targetAnchor,
        followerAnchor: followerAnchor,
        offset: offset,
        child: _AnimatedPop(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0, 8)),
                ],
              ),
              child: ClipRRect(
                borderRadius: widget.borderRadius,
                child: Image.network(
                  widget.imageUrl,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : SizedBox(
                          width: size,
                          height: size,
                          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                  errorBuilder: (_, _, _) => SizedBox(
                    width: size,
                    height: size,
                    child: Container(
                      color: Colors.grey.shade100,
                      child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) => _show(),
        onExit: (_) => _remove(),
        child: widget.child,
      ),
    );
  }
}

/// Small fade + scale-in so the popup doesn't just snap into place.
class _AnimatedPop extends StatefulWidget {
  final Widget child;
  const _AnimatedPop({required this.child});

  @override
  State<_AnimatedPop> createState() => _AnimatedPopState();
}

class _AnimatedPopState extends State<_AnimatedPop> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: ScaleTransition(
        scale: Tween(begin: 0.94, end: 1.0).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOut),
        ),
        child: widget.child,
      ),
    );
  }
}
