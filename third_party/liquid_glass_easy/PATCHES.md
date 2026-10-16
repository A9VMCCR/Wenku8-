# Wenku8 performance patch

Based on the unmodified **liquid_glass_easy 5.0.0** pub.dev source archive,
by Ahmed Gamil. The upstream MIT license is retained in `LICENSE`.

Source: https://pub.dev/packages/liquid_glass_easy/versions/5.0.0
Upstream: https://github.com/AhmeedGamil/liquid_glass_easy

## 2026-10-15 — Bound single-lens shader output

`lib/assets/shaders/liquid_glass.frag` returns transparent pixels outside the
lens's output box before evaluating its shape, normals, refraction, lights and
texture samples. A derivative guard includes the antialiasing band and expands
under inverse ancestor transforms, preserving rounded, continuous, squircle,
scaled, rotated and flex-deformed edges.

The material equations, backdrop coordinate mapping, sampling, public widgets,
gestures, blender and morph APIs are unchanged. No screen captures, frame-rate
limiter, lower-resolution glass or static backdrop is introduced.

Native pixel validation lives in the host app at
`integration_test/easy_glass_pixels_test.dart`. Profile timing comparisons use
identical scenes and settings. Record device/GPU identity with timings;
emulator results do not establish physical-device FPS.

The vendored pubspec omits the pub.dev screenshot entry because the publishing
thumbnail is not included in the app's source distribution.

## Physically rounded menu morphs

The opt-in `LiquidGlassLens.physicalOptics` keeps a host-clipped rounded plate's
radius, refraction width and Gaussian blur in screen units under positive,
axis-aligned ancestor scales. Foreground layout remains host-owned. Normal
lenses, rotations and existing callers keep the upstream local-space contract.
This preserves the app's circular menu origin without relaying out its labels.

## Stable batch inheritance

`LiquidGlassBatch.inherit` keeps the enclosing backdrop key while enabled and
isolates the subtree while disabled. The scope stays mounted across changes,
preserving focused inputs and their platform connections as a lens settles.
The existing batch and exclude constructors keep their original behavior.

## 2026-10-16 — Opacity subpass coordinates

`liquidGlassFilterSubpassAncestor` recognizes partial `OpacityLayer` alpha
(1–254) in addition to `ImageFilterLayer`, so the shader uses the fading plane's
coordinates. Alpha 255 takes the engine's direct-paint path, not an opacity
subpass. Reader header and dock have separate batch
keys because their opacity textures are different backdrop surfaces. The
native reader integration captures full, half, low and zero-opacity states.

## 2026-10-16 — App form controls

The app uses the package's `LiquidGlassSwitch`, `LiquidGlassSlider` and inline
`LiquidGlassSegmented`, with its own milk/stone palette. The pinned fork exports
the inline selector and adds disabled-item semantics and focus feedback. Label
alpha is preserved when applying the disabled treatment.

Switch, slider and motion pill accept opt-in `reduceMotion`; defaults retain the
upstream springs, finger-follow, rubber band and glass deformation. The slider
also accepts opt-in `minimumTouchHeight` (default zero). Its release reconciles
controlled/quantized values, and its initial gesture value matches its initial
thumb. The switch does not request an unused raster snapshot on Impeller.
Slider capture starts only when its motion pill actually exposes glass. A
zero-frame tap can no longer leave Skia's capture pump running after release.

The app adapters reserve the complete swell footprint, add controlled async
switch values, slider divisions, disabled input, keyboard and screen-reader
actions. They do not replace the package's gesture simulation or lens renderer.

## 2026-10-16 — Premultiplied tint at antialiased edges

The shared `applyLensTint` mixed an already coverage-multiplied backdrop toward
an unmultiplied tint using tint-alpha × coverage. This added an extra
`alpha × coverage × (1 − coverage) × backdrop` term. With the optical lights
disabled, light paper presets still developed a white outline.

Tint now mixes in the same premultiplied coverage space as the backdrop. The
interior tint, refraction, optical lights, uniform emission and shader's shape
coverage are unchanged. Both single-lens and metaball shaders share this fix.
`integration_test/support/glass_tint_edges.dart` compares actual Impeller pixels
on uniform sage/parchment/night papers; zero-light pixels must not exceed either
input color. Before repair the sage/parchment cases exceed the allowed channel
ceiling by 16/21, respectively; night already passes.
