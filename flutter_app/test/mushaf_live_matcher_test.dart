import 'package:flutter_test/flutter_test.dart';
import 'package:qurany_app/models/mushaf_layout.dart';
import 'package:qurany_app/services/mushaf_live_matcher.dart';

MushafWord _w(int id, String text) => MushafWord(
      id: id,
      text: text,
      verseKey: '12:23',
      positionInVerse: id,
      isAyahMarker: false,
    );

Map<int, MushafWordLiveState> _matchTranscript(
  List<MushafWord> ref,
  String transcript,
) {
  final matcher = MushafIncrementalMatcher()..reset(ref);
  matcher.ingestWords(MushafLiveMatcher.allWordsFromTranscript(transcript));
  return matcher.states;
}

void main() {
  group('MushafIncrementalMatcher', () {
    test('one wrong word does not mark following correct words as wrong', () {
      final ref = [
        _w(1, 'الحمد'),
        _w(2, 'لله'),
        _w(3, 'رب'),
        _w(4, 'العالمين'),
      ];

      final states = _matchTranscript(ref, 'الحمد لله كلب العالمين');

      expect(states[1]?.status, MushafWordLiveStatus.correct);
      expect(states[2]?.status, MushafWordLiveStatus.correct);
      expect(states[3]?.status, MushafWordLiveStatus.wrong);
      expect(states[4]?.status, MushafWordLiveStatus.correct);
    });

    test('skipped word is omitted and next spoken word stays aligned', () {
      final ref = [
        _w(1, 'الحمد'),
        _w(2, 'لله'),
        _w(3, 'رب'),
        _w(4, 'العالمين'),
      ];

      final states = _matchTranscript(ref, 'الحمد رب العالمين');

      expect(states[1]?.status, MushafWordLiveStatus.correct);
      expect(states[2]?.status, MushafWordLiveStatus.omitted);
      expect(states[3]?.status, MushafWordLiveStatus.correct);
      expect(states[4]?.status, MushafWordLiveStatus.correct);
    });

    test('multiple skipped words are omitted without substitution cascade', () {
      final ref = [
        _w(1, 'الحمد'),
        _w(2, 'لله'),
        _w(3, 'رب'),
        _w(4, 'العالمين'),
      ];

      final states = _matchTranscript(ref, 'الحمد العالمين');

      expect(states[1]?.status, MushafWordLiveStatus.correct);
      expect(states[2]?.status, MushafWordLiveStatus.omitted);
      expect(states[3]?.status, MushafWordLiveStatus.omitted);
      expect(states[4]?.status, MushafWordLiveStatus.correct);
    });

    test('trailing reference words stay pending for partial transcript', () {
      final ref = [
        _w(1, 'الحمد'),
        _w(2, 'لله'),
        _w(3, 'رب'),
        _w(4, 'العالمين'),
      ];

      final states = _matchTranscript(ref, 'الحمد لله');

      expect(states[1]?.status, MushafWordLiveStatus.correct);
      expect(states[2]?.status, MushafWordLiveStatus.correct);
      expect(states[3]?.status, MushafWordLiveStatus.pending);
      expect(states[4]?.status, MushafWordLiveStatus.pending);
    });

    test('Yusuf ayah: STT noise does not cascade red marks', () {
      final ref = [
        _w(1, 'وَرَاوَدَتْهُ'),
        _w(2, 'الَّتِي'),
        _w(3, 'هُوَ'),
        _w(4, 'فِي'),
        _w(5, 'بَيْتِهَا'),
        _w(6, 'وَلَقَدْ'),
        _w(7, 'هَمَّتْ'),
        _w(8, 'بِهِ'),
      ];

      final states = _matchTranscript(
        ref,
        'وراودته التي هو في بيتها الكافرون لما تبيه هم بها',
      );

      expect(states[1]?.status, MushafWordLiveStatus.correct);
      expect(states[2]?.status, MushafWordLiveStatus.correct);
      expect(states[3]?.status, MushafWordLiveStatus.correct);
      expect(states[4]?.status, MushafWordLiveStatus.correct);
      expect(states[5]?.status, MushafWordLiveStatus.correct);
      expect(states[6]?.status, isNot(MushafWordLiveStatus.wrong));
      expect(states[7]?.status, isNot(MushafWordLiveStatus.wrong));
    });

    test('mushaf orthography matches STT without diacritics', () {
      final ref = [
        _w(1, 'رَبِّى'),
        _w(2, 'إِنَّهُ'),
        _w(3, 'رَءَا'),
      ];

      final states = _matchTranscript(ref, 'ربي انه رأى');

      expect(states[1]?.status, MushafWordLiveStatus.correct);
      expect(states[2]?.status, MushafWordLiveStatus.correct);
      expect(states[3]?.status, MushafWordLiveStatus.correct);
    });

    test('unrelated short misread is marked wrong', () {
      final ref = [_w(1, 'مَعَاذَ'), _w(2, 'اللّه')];
      final states = _matchTranscript(ref, 'قال الله');

      expect(states[1]?.status, MushafWordLiveStatus.wrong);
      expect(states[1]?.recitedAs, 'قال');
      expect(states[2]?.status, MushafWordLiveStatus.correct);
    });

    test('tajweed misread يخادعون is wrong for يخدعون', () {
      final ref = [_w(1, 'يَخْدَعُونَ')];
      final states = _matchTranscript(ref, 'يخادعون');

      expect(states[1]?.status, MushafWordLiveStatus.wrong);
      expect(states[1]?.recitedAs, 'يخادعون');
    });

    test('tajweed misread يشكران is wrong for يشعرون', () {
      final ref = [_w(1, 'يَشْعُرُونَ')];
      final states = _matchTranscript(ref, 'يشكران');

      expect(states[1]?.status, MushafWordLiveStatus.wrong);
      expect(states[1]?.recitedAs, 'يشكران');
    });

    test('exact normalized match still marks correct', () {
      final ref = [_w(1, 'يَخْدَعُونَ'), _w(2, 'يَشْعُرُونَ')];
      final states = _matchTranscript(ref, 'يخدعون يشعرون');

      expect(states[1]?.status, MushafWordLiveStatus.correct);
      expect(states[2]?.status, MushafWordLiveStatus.correct);
    });

    test('STT drops final letter on longer word', () {
      final ref = [_w(1, 'آمَنُوا')];
      final states = _matchTranscript(ref, 'امنو');

      expect(states[1]?.status, MushafWordLiveStatus.correct);
    });

    test('leading basmallah in transcript is ignored for matching', () {
      final ref = [
        _w(1, 'الم'),
        _w(2, 'ذَٰلِكَ'),
      ];
      final states = _matchTranscript(
        ref,
        MushafLiveMatcher.stripLeadingBasmallahFromTranscript(
          'بسم الله الرحمن الرحيم الم ذلك',
        ),
      );

      expect(states[1]?.status, MushafWordLiveStatus.correct);
      expect(states[2]?.status, MushafWordLiveStatus.correct);
    });

    test('refWordsForMatching skips Al-Fatiha ayah 1', () {
      final pageWords = [
        _w(1, 'بِسْمِ'),
        _w(2, 'اللَّهِ'),
        _w(3, 'الرَّحْمَٰنِ'),
        _w(4, 'الرَّحِيمِ'),
        _w(5, 'الْحَمْدُ'),
      ];
      // Simulate surah 1 ayah 1 then 1:2 on same page.
      final ayah1 = pageWords.sublist(0, 4);
      final ayah2Word = pageWords[4];
      final withKeys = [
        MushafWord(
          id: ayah1[0].id,
          text: ayah1[0].text,
          verseKey: '1:1',
          positionInVerse: 1,
          isAyahMarker: false,
        ),
        ...ayah1.skip(1).map(
              (w) => MushafWord(
                id: w.id,
                text: w.text,
                verseKey: '1:1',
                positionInVerse: w.id,
                isAyahMarker: false,
              ),
            ),
        MushafWord(
          id: ayah2Word.id,
          text: ayah2Word.text,
          verseKey: '1:2',
          positionInVerse: 1,
          isAyahMarker: false,
        ),
      ];

      final matching = MushafLiveMatcher.refWordsForMatching(withKeys);
      expect(matching.length, 1);
      expect(matching.single.text, 'الْحَمْدُ');
    });

    test('mergeLiveIntoServerResult trusts server only', () {
      final merged = MushafLiveMatcher.mergeLiveIntoServerResult(
        server: {
          'similarity_score': 95.0,
          'errors': [
            {'type': 'substitution', 'expectedWord': 'رب', 'recitedWord': 'كلب'},
          ],
        },
        local: {
          'errors': [
            {'type': 'substitution', 'expectedWord': 'الحمد', 'recitedWord': 'x'},
            {'type': 'substitution', 'expectedWord': 'لله', 'recitedWord': 'y'},
          ],
        },
      );

      expect(merged['errors'], hasLength(1));
      expect(merged['similarity_score'], 95.0);
    });

    test('forward-only: second pass with shorter partial does not rewind', () {
      final ref = [_w(1, 'الحمد'), _w(2, 'لله'), _w(3, 'رب')];
      final matcher = MushafIncrementalMatcher()..reset(ref);
      matcher.ingestWords(['الحمد', 'لله']);
      expect(matcher.states[1]?.status, MushafWordLiveStatus.correct);
      expect(matcher.states[2]?.status, MushafWordLiveStatus.correct);
      // Shorter partial after breath — nothing new to ingest.
      matcher.ingestWords(MushafLiveMatcher.committedWordsFromTranscript('الحمد'));
      expect(matcher.states[1]?.status, MushafWordLiveStatus.correct);
      expect(matcher.states[2]?.status, MushafWordLiveStatus.correct);
      matcher.ingestWords(['رب']);
      expect(matcher.states[3]?.status, MushafWordLiveStatus.correct);
    });

    test('mergeTranscriptSegment appends post-breath segment without overlap', () {
      final merged = MushafLiveMatcher.mergeTranscriptSegment(
        'الحمد لله',
        'رب العالمين',
      );
      expect(merged, 'الحمد لله رب العالمين');
    });

    test('realignToCommitted resumes after breath-style gap', () {
      final ref = [
        _w(1, 'الحمد'),
        _w(2, 'لله'),
        _w(3, 'رب'),
        _w(4, 'العالمين'),
      ];
      final matcher = MushafIncrementalMatcher()..reset(ref);
      matcher.ingestWords(['الحمد', 'لله']);
      expect(matcher.processedTransCount, 2);

      final afterBreath = MushafLiveMatcher.allWordsFromTranscript(
        MushafLiveMatcher.mergeTranscriptSegment('الحمد لله', 'رب العالمين'),
      );
      matcher.realignToCommitted(afterBreath);
      expect(matcher.states[1]?.status, MushafWordLiveStatus.correct);
      expect(matcher.states[2]?.status, MushafWordLiveStatus.correct);
      expect(matcher.states[3]?.status, MushafWordLiveStatus.correct);
      expect(matcher.states[4]?.status, MushafWordLiveStatus.correct);
    });
  });
}
