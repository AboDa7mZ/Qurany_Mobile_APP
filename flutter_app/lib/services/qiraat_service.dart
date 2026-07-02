import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QiraatService extends ChangeNotifier {
  static const String _storageKey = 'selected_qiraat';
  final SharedPreferences _prefs;
  
  String _selectedQiraat = 'حفص';

  QiraatService(this._prefs) {
    _loadQiraat();
  }

  String get selectedQiraat => _selectedQiraat;

  void _loadQiraat() {
    _selectedQiraat = _prefs.getString(_storageKey) ?? 'حفص';
  }

  Future<void> setQiraat(String qiraat) async {
    _selectedQiraat = qiraat;
    await _prefs.setString(_storageKey, qiraat);
    notifyListeners();
  }
}
