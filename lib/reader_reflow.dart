import 'dart:ui' show lerpDouble;
import 'package:flutter/widgets.dart';
import 'archive_motion.dart';
import 'reader_pagination.dart';
import 'reader_turn_motion.dart';

/// Reflow retains source identities. Changed vertical columns are replaced in
/// reading order while unchanged glyphs stay painted in place.
class ReaderReflowScope extends InheritedWidget {
  const ReaderReflowScope({
    super.key,
    required this.animation,
    required this.previous,
    required this.size,
    required this.previousSize,
    required this.originDelta,
    required super.child,
  });
  final Animation<double> animation;
  final ReaderLeaf previous;
  final Size size, previousSize;
  final Offset originDelta;
  double get progress =>
      Curves.easeOutCubic.transform(animation.value.clamp(0, 1));
  double delayFor(int index, int count, {bool reverse = false}) {
    final rank = reverse ? count - 1 - index : index;
    return count < 2 ? 0 : .2 * rank.clamp(0, count - 1) / (count - 1);
  }

  double progressFor(int index, int count, {bool reverse = false}) {
    final start = delayFor(index, count, reverse: reverse);
    return Interval(
      start,
      start + .8,
      curve: Curves.easeOutCubic,
    ).transform(animation.value.clamp(0, 1));
  }

  Offset displacementFor(int index, int count, {bool reverse = false}) =>
      originDelta * (progress - progressFor(index, count, reverse: reverse));
  static ReaderReflowScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReaderReflowScope>();
  @override
  bool updateShouldNotify(ReaderReflowScope oldWidget) =>
      animation != oldWidget.animation ||
      previous != oldWidget.previous ||
      size != oldWidget.size ||
      previousSize != oldWidget.previousSize ||
      originDelta != oldWidget.originDelta;
}

/// The existing paragraph moves as one piece. Only newly exposed paragraphs
/// borrow the same finite slide/reveal clock as the archive's loaded content.
class ReaderFragmentMotion extends StatelessWidget {
  const ReaderFragmentMotion({
    super.key,
    required this.fragment,
    required this.index,
    required this.count,
    required this.child,
  });
  final ReaderPageFragment fragment;
  final int index, count;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final scope = ReaderReflowScope.maybeOf(context);
    if (scope == null) {
      return ReaderTurnPart(
        index: index,
        count: count,
        bounds: fragment.rect,
        child: child,
      );
    }
    final reverse = scope.originDelta.dy < 0;
    ReaderPageFragment? previous;
    for (final before in scope.previous.fragments) {
      if (before.paragraph == fragment.paragraph &&
          before.start == fragment.start) {
        previous = before;
        break;
      }
    }
    final old = previous;
    final start = scope.delayFor(index, count, reverse: reverse);
    return AnimatedBuilder(
      animation: scope.animation,
      child: old != null
          ? child
          : ArchiveReveal(
              animation: scope.animation,
              start: start,
              end: start + .8,
              travel: const Offset(-8, 10),
              child: child,
            ),
      builder: (context, child) {
        final progress = scope.progressFor(index, count, reverse: reverse);
        final correction = old == null
            ? Offset.zero
            : (old.rect.topLeft - fragment.rect.topLeft) * (1 - progress);
        return Transform.translate(
          offset:
              scope.displacementFor(index, count, reverse: reverse) +
              correction,
          child: child,
        );
      },
    );
  }
}

/// Paint-only viewport interpolation. Pagination always sees the final size,
/// so opening controls never shapes a chapter on every animation tick.
class ReaderIncrementalViewport extends StatelessWidget {
  const ReaderIncrementalViewport({
    super.key,
    required this.animation,
    required this.fromSize,
    required this.toSize,
    required this.originDelta,
    required this.child,
    this.removedTail,
    this.horizontalOverflow = 0,
  });
  final Animation<double> animation;
  final Size fromSize, toSize;
  final Offset originDelta;
  final Widget child;
  final Widget? removedTail;
  final double horizontalOverflow;
  Rect viewportAt(double value) {
    final t = Curves.easeOutCubic.transform(value.clamp(0, 1));
    return Offset.lerp(originDelta, Offset.zero, t)! &
        Size(
          lerpDouble(fromSize.width, toSize.width, t)!,
          lerpDouble(fromSize.height, toSize.height, t)!,
        );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        child,
        if (removedTail != null)
          IgnorePointer(
            child: ExcludeSemantics(
              child: SelectionContainer.disabled(
                child: ClipRect(
                  clipper: _TailClip(toSize.height, fromSize),
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: fromSize.width,
                    maxWidth: fromSize.width,
                    minHeight: fromSize.height,
                    maxHeight: fromSize.height,
                    child: removedTail,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
    builder: (context, child) {
      final viewport = viewportAt(animation.value);
      return ClipRect(
        clipper: _ViewportClip(
          Rect.fromLTRB(
            (viewport.left > 0 ? 0 : viewport.left) - horizontalOverflow,
            viewport.top > 0 ? 0 : viewport.top,
            viewport.right + horizontalOverflow,
            viewport.bottom,
          ),
        ),
        child: Transform.translate(offset: viewport.topLeft, child: child),
      );
    },
  );
}

class _ViewportClip extends CustomClipper<Rect> {
  const _ViewportClip(this.rect);
  final Rect rect;
  @override
  Rect getClip(Size size) => rect;
  @override
  bool shouldReclip(_ViewportClip oldClipper) => oldClipper.rect != rect;
}

class _TailClip extends CustomClipper<Rect> {
  const _TailClip(this.top, this.original);
  final double top;
  final Size original;
  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    top.clamp(0, original.height),
    original.width,
    original.height,
  );
  @override
  bool shouldReclip(_TailClip oldClipper) =>
      oldClipper.top != top || oldClipper.original != original;
}
