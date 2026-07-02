import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qurany_app/models/recitation_session.dart';
import 'package:qurany_app/services/recitation_history_service.dart';

RecitationSession _session({required String id}) {
  return RecitationSession(
    id: id,
    surahNumber: 78,
    surahName: 'النبأ',
    mode: 'free',
    dateTime: DateTime(2026, 7, 3, 12),
    similarityScore: 0.91,
    totalWords: 10,
    matchedWords: 9,
    mistakes: 1,
  );
}

void main() {
  test('adds and removes sessions from local storage', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = RecitationHistoryService(prefs);

    await service.addSession(_session(id: 's1'));
    expect(service.sessions, hasLength(1));
    expect(service.totalSessions, 1);

    await service.removeSession('s1');
    expect(service.sessions, isEmpty);
  });

  test('reloads persisted history after restart', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = RecitationHistoryService(prefs);
    await service.addSession(_session(id: 's1'));

    final reloaded = RecitationHistoryService(prefs);
    expect(reloaded.sessions.single.id, 's1');
  });
}
