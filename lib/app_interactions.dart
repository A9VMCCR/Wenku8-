import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_ui.dart';

final _routeSlots = Expando<Set<Object>>('novel-route-slots');
final _feedbackEntries = Expando<VoidCallback>('novel-feedback');

/// The slot belongs to one Navigator, not the app. Different destinations can
/// nest normally; repeated activation of the same destination opens one route.
Future<T?> pushNovelPage<T>(
  BuildContext context,
  Widget page, {
  required bool reduceMotion,
  Object? slot,
  bool paperFlight = false,
}) async {
  if (!context.mounted) return null;
  final navigator = Navigator.of(context);
  final slots = _routeSlots[navigator] ??= <Object>{};
  final key = slot ?? page.runtimeType;
  if (!slots.add(key)) return null;
  final route = softRoute<T>(
    page,
    reduceMotion: reduceMotion || MediaQuery.disableAnimationsOf(context),
    paperFlight: paperFlight,
  );
  try {
    // Android back may hide the IME while its EditableText stays focused.
    // Clear that scope's focus history before the route can restore it on pop.
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await navigator.push(route);
    await route.completed;
    return result;
  } finally {
    slots.remove(key);
  }
}

/// A single app-wide glass notice, below the header rather than over the Dock.
/// The root overlay keeps feedback from a sheet visible above that sheet too.
void showNovelFeedback(
  BuildContext context,
  String message, {
  String? actionLabel,
  FutureOr<void> Function()? action,
  String actionFailure = '操作保存失败，请重试',
}) {
  if (!context.mounted) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _feedbackEntries[overlay]?.call();
  final themes = InheritedTheme.capture(from: context, to: overlay.context);
  final appearance = GlassAppearance.of(context);
  late OverlayEntry entry;
  var removed = false;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
    entry.dispose();
    if (identical(_feedbackEntries[overlay], remove)) {
      _feedbackEntries[overlay] = null;
    }
  }

  entry = OverlayEntry(
    builder: (_) => themes.wrap(
      GlassAppearance(
        blur: appearance.blur,
        opacity: appearance.opacity,
        child: NovelFeedbackNotice(
          message: message,
          actionLabel: actionLabel,
          onAction: action == null || actionLabel == null
              ? null
              : () async {
                  remove();
                  try {
                    await action();
                  } catch (_) {
                    if (context.mounted) {
                      showNovelFeedback(context, actionFailure);
                    }
                  }
                },
          onDismiss: remove,
        ),
      ),
    ),
  );
  _feedbackEntries[overlay] = remove;
  overlay.insert(entry);
}

class NovelFeedbackNotice extends StatefulWidget {
  const NovelFeedbackNotice({
    super.key,
    required this.message,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });
  final String message;
  final String? actionLabel;
  final VoidCallback onDismiss;
  final Future<void> Function()? onAction;
  @override
  State<NovelFeedbackNotice> createState() => _NovelFeedbackNoticeState();
}

class _NovelFeedbackNoticeState extends State<NovelFeedbackNotice>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: NovelMotion.enter,
    reverseDuration: NovelMotion.contact,
  );
  Timer? _timer;
  bool _started = false, _closing = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.value = 1;
    } else {
      _motion.forward();
    }
    // Notices are transient even with a screen reader. Give long copy and
    // actions more reading time, but never require a separate close control.
    final seconds = (widget.message.runes.length / 14).ceil().clamp(
      widget.onAction == null ? 4 : 6,
      12,
    );
    _timer = Timer(
      Duration(
        seconds: MediaQuery.accessibleNavigationOf(context)
            ? math.max(10, seconds)
            : seconds,
      ),
      _close,
    );
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    if (!MediaQuery.disableAnimationsOf(context)) {
      try {
        await _motion.reverse().orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = media.viewPadding.top + FrostedHeader.toolbarHeight + 12;
    // 54 dp Dock + 12 dp bottom gap + deformation and separation. Long
    // messages scroll inside the notice rather than reaching into this band.
    final bottom = math.max(
      media.viewInsets.bottom + 16,
      media.viewPadding.bottom + 88,
    );
    return Positioned(
      top: top,
      left: media.viewPadding.left + 16,
      right: media.viewPadding.right + 16,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: (media.size.height - top - bottom).clamp(
              0,
              double.infinity,
            ),
          ),
          child: AnimatedBuilder(
            animation: _motion,
            child: Semantics(
              liveRegion: true,
              container: true,
              child: LiquidGlass(
                key: const ValueKey('novel-feedback-surface'),
                radius: 24,
                elevated: false,
                blur: GlassAppearance.of(context).blur,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    if (widget.onAction != null && widget.actionLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: GlassTextButton(
                          onPressed: widget.onAction,
                          child: Text(widget.actionLabel!),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            builder: (context, child) {
              final value = NovelMotion.ease.transform(_motion.value);
              // Reveal the actual glass rather than isolating its live backdrop
              // in a fractional-opacity layer.
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: value,
                  child: Transform.translate(
                    offset: Offset(0, -12 * (1 - value)),
                    child: child,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
