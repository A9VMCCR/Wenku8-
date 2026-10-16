import 'package:flutter/material.dart';
import 'app_ui.dart';

class ReaderSelectionController extends ValueNotifier<bool> {
  ReaderSelectionController() : super(false);
  final key = GlobalKey<SelectionAreaState>();
  void clear() {
    key.currentState?.selectableRegion.clearSelection();
    value = false;
  }
}

/// Native range selection, with the app's existing glass material. No editable
/// field, keyboard request, note storage or per-paragraph gesture recognizers.
class ReaderSelection extends StatelessWidget {
  const ReaderSelection({
    super.key,
    required this.controller,
    required this.child,
    this.onSelect,
    this.vertical = false,
  });
  final ReaderSelectionController controller;
  final Widget child;
  final VoidCallback? onSelect;
  final bool vertical;
  @override
  Widget build(BuildContext context) => SelectionArea(
    key: controller.key,
    onSelectionChanged: (content) {
      final active = content?.plainText.isNotEmpty == true;
      if (active && !controller.value) onSelect?.call();
      controller.value = active;
    },
    contextMenuBuilder: (context, region) {
      var anchors = region.contextMenuAnchors;
      final points = region.selectionEndpoints;
      if (vertical && points.length == 2) {
        final box = region.context.findRenderObject()! as RenderBox;
        final start = box.localToGlobal(points.first.point);
        final end = box.localToGlobal(points.last.point);
        final x = (start.dx + end.dx) / 2;
        anchors = TextSelectionToolbarAnchors(
          primaryAnchor: Offset(x, start.dy < end.dy ? start.dy : end.dy),
          secondaryAnchor: Offset(x, start.dy > end.dy ? start.dy : end.dy),
        );
      }
      return CustomSingleChildLayout(
        delegate: TextSelectionToolbarLayoutDelegate(
          anchorAbove: anchors.primaryAnchor - const Offset(0, 8),
          anchorBelow:
              (anchors.secondaryAnchor ?? anchors.primaryAnchor) +
              const Offset(0, 8),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: GlassOverlaySurface(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in region.contextMenuButtonItems)
                    if (item.type == ContextMenuButtonType.copy)
                      GlassTextButton(
                        key: ValueKey('reader-selection-${item.type.name}'),
                        onPressed: item.onPressed,
                        child: const Text('复制'),
                      ),
                ],
              ),
            ),
          ),
        ),
      );
    },
    child: child,
  );
}
