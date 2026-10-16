import 'dart:convert';
import 'package:flutter/material.dart';
import 'archive_design.dart';

enum ReaderPaper {
  system('跟随外观'),
  milk('奶白'),
  parchment('羊皮纸'),
  sage('浅苔'),
  night('夜读');

  const ReaderPaper(this.label);
  final String label;
}

enum ReaderMode {
  scroll('上下滚动'),
  paged('横排翻页'),
  vertical('竖排翻页');

  const ReaderMode(this.label);
  final String label;
  bool get paginated => this != scroll;
}

enum ReaderTapLayout {
  standard('常规'),
  rightHand('右手'),
  leftHand('左手');

  const ReaderTapLayout(this.label);
  final String label;
}

/// Reader-only settings: changing paper never changes the rest of the app.
class ReaderPreferences {
  const ReaderPreferences({
    this.paper = ReaderPaper.system,
    this.margin = 26,
    this.paragraphGap = 12,
    this.indent = false,
    this.justify = false,
    this.tapPaging = false,
    this.volumePaging = false,
    this.brightness,
    this.autoScrollSpeed = 24,
    this.mode = ReaderMode.scroll,
    this.tapLayout = ReaderTapLayout.standard,
    this.edgeBrightness = false,
  });
  final ReaderPaper paper;
  final double margin, paragraphGap, autoScrollSpeed;
  final bool indent, justify, tapPaging, volumePaging;
  final double? brightness;
  final ReaderMode mode;
  final ReaderTapLayout tapLayout;
  final bool edgeBrightness;
  String get layoutKey =>
      margin == 26 &&
          paragraphGap == 12 &&
          !indent &&
          !justify &&
          mode == ReaderMode.scroll
      ? ''
      : '$margin:$paragraphGap:$indent:$justify${mode == ReaderMode.scroll ? '' : ':${mode.name}'}';
  Color background(bool dark) => switch (paper) {
    ReaderPaper.system =>
      dark ? ArchiveDesign.darkBackground : const Color(0xFFF7F7F2),
    ReaderPaper.milk => const Color(0xFFF6F5EF),
    ReaderPaper.parchment => const Color(0xFFEDE2CA),
    ReaderPaper.sage => const Color(0xFFE4EBDD),
    ReaderPaper.night => ArchiveDesign.darkBackground,
  };
  Color foreground(bool dark) =>
      paper == ReaderPaper.night || paper == ReaderPaper.system && dark
      ? ArchiveDesign.darkInk
      : const Color(0xFF30352F);
  Map<String, Object?> toJson() => {
    'paper': paper.name,
    'margin': margin,
    'paragraphGap': paragraphGap,
    'indent': indent,
    'justify': justify,
    'tapPaging': tapPaging,
    'volumePaging': volumePaging,
    'brightness': brightness,
    'autoScrollSpeed': autoScrollSpeed,
    'mode': mode.name,
    'tapLayout': tapLayout.name,
    'edgeBrightness': edgeBrightness,
  };
  factory ReaderPreferences.fromJson(Map<String, dynamic> json) {
    double number(String key, double min, double max, double fallback) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw const FormatException('阅读偏好数值超出范围');
      }
      return value.toDouble();
    }

    for (final key in [
      'indent',
      'justify',
      'tapPaging',
      'volumePaging',
      'edgeBrightness',
    ]) {
      if (json[key] != null && json[key] is! bool) {
        throw const FormatException('阅读偏好格式有误');
      }
    }
    return ReaderPreferences(
      paper: ReaderPaper.values.firstWhere(
        (p) => p.name == (json['paper'] ?? 'system'),
      ),
      margin: number('margin', 12, 56, 26),
      paragraphGap: number('paragraphGap', 0, 32, 12),
      indent: json['indent'] == true,
      justify: json['justify'] == true,
      tapPaging: json['tapPaging'] == true,
      volumePaging: json['volumePaging'] == true,
      brightness: json['brightness'] == null
          ? null
          : number('brightness', .03, 1, 1),
      autoScrollSpeed: number('autoScrollSpeed', 8, 80, 24),
      mode: ReaderMode.values.byName(json['mode'] ?? 'scroll'),
      tapLayout: ReaderTapLayout.values.byName(json['tapLayout'] ?? 'standard'),
      edgeBrightness: json['edgeBrightness'] == true,
    );
  }
  static ReaderPreferences fromRecord(Object? record) {
    try {
      return ReaderPreferences.fromJson(jsonDecode(record as String));
    } catch (_) {
      return const ReaderPreferences();
    }
  }

  ReaderPreferences copyWith({
    ReaderPaper? paper,
    double? margin,
    double? paragraphGap,
    bool? indent,
    bool? justify,
    bool? tapPaging,
    bool? volumePaging,
    double? brightness,
    bool systemBrightness = false,
    double? autoScrollSpeed,
    ReaderMode? mode,
    ReaderTapLayout? tapLayout,
    bool? edgeBrightness,
  }) => ReaderPreferences(
    paper: paper ?? this.paper,
    margin: margin ?? this.margin,
    paragraphGap: paragraphGap ?? this.paragraphGap,
    indent: indent ?? this.indent,
    justify: justify ?? this.justify,
    tapPaging: tapPaging ?? this.tapPaging,
    volumePaging: volumePaging ?? this.volumePaging,
    brightness: systemBrightness ? null : brightness ?? this.brightness,
    autoScrollSpeed: autoScrollSpeed ?? this.autoScrollSpeed,
    mode: mode ?? this.mode,
    tapLayout: tapLayout ?? this.tapLayout,
    edgeBrightness: edgeBrightness ?? this.edgeBrightness,
  );
}
