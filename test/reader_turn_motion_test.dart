import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/reader_content.dart';
import 'package:wenku8_flutter/reader_book_layout.dart';
import 'package:wenku8_flutter/reader_paged_view.dart';
import 'package:wenku8_flutter/reader_pagination.dart';
import 'package:wenku8_flutter/reader_preferences.dart';
import 'package:wenku8_flutter/reader_reflow.dart';
import 'package:wenku8_flutter/reader_turn_motion.dart';
import 'package:wenku8_flutter/reader_vertical_text.dart';

import 'reader_modes_test.dart' show settleReader;
import 'support/visual_review.dart';

const _style = TextStyle(fontSize: 19, height: 1.72, color: Color(0xff373a3d));
final _content = ReaderContent([
  for (var i = 0; i < 80; i++)
    '第${i + 1}段　窗外的风轻轻掠过书页，她停下脚步。「往前走吧，下一页的故事正等着我们。」',
]);

Widget _page(ReaderLeaf page, ReaderMode mode, ReaderGlyphCache cache) =>
    mode == ReaderMode.vertical
    ? ReaderVerticalText(page: page, style: _style, glyphCache: cache)
    : Stack(
        clipBehavior: Clip.none,
        children: [
          for (final (index, fragment) in page.fragments.indexed)
            Positioned.fromRect(
              rect: fragment.rect,
              child: ReaderFragmentMotion(
                fragment: fragment,
                index: index,
                count: page.fragments.length,
                child: Text(
                  '${fragment.indent ? '\u3000\u3000' : ''}${fragment.text}',
                  style: _style,
                ),
              ),
            ),
        ],
      );

void main({
  bool native = false,
  Future<void> Function(WidgetTester, GlobalKey, String)? capture,
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!native) setUpAll(loadReviewFonts);
  test('one paragraph arrives before the later paragraphs start', () {
    const scope = ReaderTurnScope(
      animation: AlwaysStoppedAnimation(.34),
      direction: 1,
      child: SizedBox(),
    );
    expect(scope.progressFor(0, 7), greaterThan(.95));
    expect(scope.progressFor(3, 7), 0);
    expect(scope.progressFor(6, 7), 0);
    expect(scope.opacityFor(0, 7), 1);
    expect(scope.opacityFor(6, 7), 0);
  });
  test(
    'book arrival finishes its first reading leaf before starting the second',
    () {
      ReaderTurnScope leaf(double time, int slot) => ReaderTurnScope(
        animation: AlwaysStoppedAnimation(time),
        direction: 1,
        slot: slot,
        slots: 2,
        child: const SizedBox(),
      );
      expect(leaf(.34, 0).progressFor(0, 7), 1);
      expect(leaf(.34, 0).progressFor(6, 7), inExclusiveRange(0, 1));
      expect(leaf(.49, 1).progressFor(0, 7), 0);
      expect(leaf(.51, 0).progressFor(6, 7), 1);
      expect(leaf(.51, 1).progressFor(0, 7), 0);
      expect(leaf(.7, 1).progressFor(0, 7), greaterThan(.95));
      expect(leaf(.7, 1).progressFor(6, 7), 0);
    },
  );

  Future<void> shot(WidgetTester tester, GlobalKey key, String name) async {
    if (capture != null) {
      await capture(tester, key, name);
    } else {
      await captureReview(tester, key, name);
    }
  }

  for (final mode in [ReaderMode.paged, ReaderMode.vertical]) {
    for (final wide in [false, true]) {
      testWidgets(
        '${mode.name} ${wide ? 'book' : 'phone'} turns paragraphs/columns, not side masks',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(wide ? 1024 : 390, 844);
          tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
          tester.view.viewPadding = tester.view.padding;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetPadding);
          addTearDown(tester.view.resetViewPadding);
          final controller = ReaderPagedController();
          final cache = ReaderGlyphCache();
          addTearDown(cache.dispose);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: novelTheme(Brightness.light),
                home: Material(
                  color: const Color(0xfff4f2eb),
                  child: ReaderPagedView(
                    content: _content,
                    preferences: ReaderPreferences(mode: mode),
                    style: _style,
                    controller: controller,
                    title: '春风 · 正文逐段滑入',
                    padding: const EdgeInsets.fromLTRB(26, 56, 26, 40),
                    onReady: () {},
                    onChanged: () {},
                    onUserScroll: () {},
                    onBoundary: (_) {},
                    pageBuilder: (page) => _page(page, mode, cache),
                  ),
                ),
              ),
            ),
          );
          await settleReader(tester);
          final generation = controller.debugLayoutGeneration;
          expect(controller.pagesPerSpread, wide ? 2 : 1);
          expect(controller.pageBy(1), true);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 180));
          final scopes = tester
              .widgetList<ReaderTurnScope>(find.byType(ReaderTurnScope))
              .where((s) => s.enabled)
              .toList();
          final incoming = scopes.where((s) => !s.outgoing).first;
          expect(incoming.animation.value, inExclusiveRange(0, 1));
          expect(incoming.direction, mode == ReaderMode.vertical ? -1 : 1);
          expect(find.byType(ArchivePlaneTransition), findsNothing);
          expect(
            tester
                .widget<ReaderIncrementalViewport>(
                  find.byType(ReaderIncrementalViewport),
                )
                .horizontalOverflow,
            0,
          );
          expect(
            tester
                .widgetList<ReaderBookSpread>(find.byType(ReaderBookSpread))
                .every((spread) => spread.edgeOverflow == 0),
            true,
            reason: 'Sliding parts stay inside the page, not in its margins.',
          );
          final layouts = <ReaderTurnPartRender, int>{};
          if (mode == ReaderMode.paged) {
            for (final element
                in find
                    .byElementPredicate(
                      (e) => e.renderObject is ReaderTurnPartRender,
                    )
                    .evaluate()) {
              final render = element.renderObject! as ReaderTurnPartRender;
              layouts[render] = render.debugLayoutCount;
            }
            final parts = layouts.keys
                .where(
                  (r) =>
                      r.scope.enabled && !r.scope.outgoing && r.scope.slot == 0,
                )
                .toList();
            expect(parts.length, greaterThan(1));
            expect(parts.first.progress, greaterThan(parts.last.progress));
            expect(parts.first.displacement, isNot(parts.last.displacement));
          } else {
            final firstLeaf = find.byWidgetPredicate(
              (w) =>
                  w is ReaderTurnScope &&
                  w.enabled &&
                  !w.outgoing &&
                  w.slot == 0,
            );
            final render = tester.renderObject<RenderReaderVerticalText>(
              find
                  .descendant(
                    of: firstLeaf,
                    matching: find.byType(ReaderVerticalText),
                  )
                  .first,
            );
            expect(render.debugTurnColumnCount, greaterThan(1));
            expect(
              render.debugTurnColumnProgress(0),
              greaterThan(
                render.debugTurnColumnProgress(render.debugTurnColumnCount - 1),
              ),
            );
          }
          final shaped = cache.debugShapeCount;
          await shot(
            tester,
            boundary,
            '${mode.name}-${wide ? 'book' : 'phone'}-turn',
          );
          await tester.pump(const Duration(milliseconds: 60));
          for (final entry in layouts.entries) {
            expect(entry.key.debugLayoutCount, entry.value);
          }
          expect(
            cache.debugShapeCount,
            shaped,
            reason: 'Animation ticks reuse shaped text.',
          );
          expect(controller.debugLayoutGeneration, generation);
          await tester.pumpAndSettle();
          expect(controller.page, controller.pagesPerSpread);
          expect(
            find.byWidgetPredicate((w) => w is ReaderTurnScope && w.enabled),
            findsNothing,
          );
          await shot(
            tester,
            boundary,
            '${mode.name}-${wide ? 'book' : 'phone'}-complete',
          );

          // Interrupted and reversed tap turns must keep the target leaf and stop.
          controller.pageBy(1);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 55));
          controller.pageBy(-1);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 60));
          final back = tester
              .widgetList<ReaderTurnScope>(find.byType(ReaderTurnScope))
              .firstWhere((s) => s.enabled && !s.outgoing);
          expect(
            back.animation.value,
            lessThan(.2),
            reason:
                'Reversing an unfinished turn retracts its existing wave instead of rebuilding another spread.',
          );
          await tester.pumpAndSettle();
          expect(controller.page, controller.pagesPerSpread);

          final viewport = find.byType(PageView);
          final size = tester.getSize(viewport);
          expect(size.width, wide ? 1024 : 390);
          final currentSpread = controller.page ~/ controller.pagesPerSpread;
          final direction = mode == ReaderMode.vertical ? 1 : -1;
          final gesture = await tester.startGesture(tester.getCenter(viewport));
          await gesture.moveBy(Offset(size.width * .32 * direction, 0));
          await tester.pump();
          await tester.pump();
          final drag = tester
              .widgetList<ReaderTurnScope>(find.byType(ReaderTurnScope))
              .firstWhere((s) => s.enabled && !s.outgoing);
          expect(drag.animation.value, inExclusiveRange(.1, .5));
          final held = drag.animation.value;
          await tester.pump(const Duration(milliseconds: 100));
          expect(
            drag.animation.value,
            held,
            reason: 'The finger, not a second timer, owns the drag.',
          );
          final before = tester.getRect(
            find.byKey(ValueKey('reader-book-spread-$currentSpread')),
          );
          final after = tester.getRect(
            find.byKey(ValueKey('reader-book-spread-${currentSpread + 1}')),
          );
          expect(before.left, closeTo(26, .01));
          expect(after.left, closeTo(26, .01));
          expect(before.right, closeTo(size.width - 26, .01));
          expect(
            after.right,
            closeTo(size.width - 26, .01),
            reason:
                'Only paragraphs move; both page planes stay within their original margins.',
          );
          await shot(
            tester,
            boundary,
            '${mode.name}-${wide ? 'book' : 'phone'}-drag',
          );
          // Return the held page instead of committing it.
          await gesture.moveBy(Offset(-size.width * .32 * direction, 0));
          await tester.pump(const Duration(milliseconds: 200));
          await gesture.up();
          await tester.pumpAndSettle();
          expect(controller.page, controller.pagesPerSpread);
          expect(
            find.byWidgetPredicate((w) => w is ReaderTurnScope && w.enabled),
            findsNothing,
          );

          await tester.drag(viewport, Offset(size.width * .8 * direction, 0));
          await tester.pumpAndSettle();
          expect(controller.page, controller.pagesPerSpread * 2);
          await tester.drag(viewport, Offset(-size.width * .8 * direction, 0));
          await tester.pumpAndSettle();
          expect(controller.page, controller.pagesPerSpread);
          expect(controller.debugLayoutGeneration, generation);
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
