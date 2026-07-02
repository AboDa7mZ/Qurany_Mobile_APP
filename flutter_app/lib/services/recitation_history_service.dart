import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/recitation_session.dart';



/// Local-only recitation history (SharedPreferences). Not synced to backend.

class RecitationHistoryService extends ChangeNotifier {

  final SharedPreferences _prefs;

  List<RecitationSession> _sessions = [];



  RecitationHistoryService(this._prefs) {

    _loadSessions();

  }



  List<RecitationSession> get sessions => List.unmodifiable(_sessions);



  void reloadFromStorage() {

    _loadSessions();

    notifyListeners();

  }



  void _loadSessions() {

    final data = _prefs.getString('recitation_history');

    if (data != null) {

      final list = json.decode(data) as List;

      _sessions = list

          .map((e) => RecitationSession.fromJson(e))

          .where((session) => !session.sync.isDeleted)

          .toList();

      _sessions.sort((a, b) => b.dateTime.compareTo(a.dateTime));

    }

  }



  Future<void> _saveSessions() async {

    final data = json.encode(_sessions.map((s) => s.toJson()).toList());

    await _prefs.setString('recitation_history', data);

  }



  Future<void> addSession(RecitationSession session) async {

    _sessions.insert(0, session);

    await _saveSessions();

    notifyListeners();

  }



  Future<void> removeSession(String id) async {

    _sessions.removeWhere((s) => s.id == id);

    await _saveSessions();

    notifyListeners();

  }



  Future<void> clearAll() async {

    _sessions = [];

    await _saveSessions();

    notifyListeners();

  }



  int get totalSessions => sessions.length;



  double get averageScore {

    if (sessions.isEmpty) return 0;

    return sessions.map((s) => s.similarityScore).reduce((a, b) => a + b) /

        sessions.length;

  }



  int get totalVersesRecited {

    return sessions.fold(0, (sum, s) => sum + s.versesRecited);

  }



  int get totalMistakes {

    return sessions.fold(0, (sum, s) => sum + s.mistakes);

  }



  Map<String, int> get surahRecitationCount {

    final counts = <String, int>{};

    for (final session in sessions) {

      counts[session.surahName] = (counts[session.surahName] ?? 0) + 1;

    }

    return counts;

  }



  List<RecitationSession> getSessionsForSurah(int surahNumber) {

    return sessions.where((s) => s.surahNumber == surahNumber).toList();

  }



  List<RecitationSession> getRecentSessions(int days) {

    final cutoff = DateTime.now().subtract(Duration(days: days));

    return sessions.where((s) => s.dateTime.isAfter(cutoff)).toList();

  }

}

