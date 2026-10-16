import 'package:flutter/foundation.dart';

import 'library_state.dart';
import 'network_status.dart';

/// Stable page identities: changing dock membership never renumbers the pages
/// or disposes their reading/search/scroll state.
class HomeNavigation extends ChangeNotifier {
  HomeNavigation(this.preferences, this.network) {
    preferences.navigationChanges.addListener(_changed);
    network?.addListener(_changed);
    _value = _read();
  }

  final LibraryState preferences;
  final NetworkStatus? network;
  late ({bool localReader, bool cachedShelf}) _value;

  ({bool localReader, bool cachedShelf}) _read() => (
    localReader: preferences.localReaderMode,
    cachedShelf: preferences.adaptWhenOffline && (network?.offline ?? false),
  );

  bool get cachedShelf => _value.cachedShelf;
  bool get localReader => _value.localReader;
  List<int> get tabs => localReader
      ? const [2, 3]
      : cachedShelf
      ? const [1, 2, 3]
      : const [0, 1, 2, 3];

  int destination(int current) => tabs.contains(current)
      ? current
      : localReader
      ? 2
      : 1;

  void _changed() {
    final next = _read();
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    preferences.navigationChanges.removeListener(_changed);
    network?.removeListener(_changed);
    super.dispose();
  }
}
