/// A metadata query for the device's known books. Keywords are partial matches;
/// spaces join terms with AND, while # limits a term to tags/classification.
class BookSearch {
  BookSearch(String query)
    : terms = [
        for (final part in _width(query).trim().split(RegExp(r'\s+')))
          if (part.isNotEmpty)
            (
              tag: part.startsWith('#'),
              text: _normalize(part.startsWith('#') ? part.substring(1) : part),
            ),
      ];
  final List<({bool tag, String text})> terms;

  static String _width(String value) => String.fromCharCodes([
    for (final rune in value.runes)
      if (rune >= 0xff01 && rune <= 0xff5e)
        rune - 0xfee0
      else if (rune == 0x3000)
        0x20
      else
        rune,
  ]);
  static final _spacing = RegExp(r'[\s·・_\-—–，,。.:：()（）\[\]【】「」『』《》]');
  static String _normalize(String value) =>
      _width(value).toLowerCase().replaceAll(_spacing, '');

  bool matches({
    required String title,
    required String author,
    required String tags,
    String summary = '',
    String id = '',
    String classification = '',
  }) {
    if (terms.isEmpty) return true;
    final tagText = _normalize('$tags $classification');
    final fields = [
      _normalize(title),
      _normalize(author),
      tagText,
      _normalize(summary),
      id,
    ];
    return terms.every(
      (term) =>
          term.text.isNotEmpty &&
          (term.tag
              ? tagText.contains(term.text)
              : fields.any((field) => field.contains(term.text))),
    );
  }
}
