import '../models/mushaf_layout.dart';

enum MushafWordLiveStatus { pending, correct, wrong, omitted }

class MushafWordLiveState {
  final MushafWordLiveStatus status;
  final String? recitedAs;

  const MushafWordLiveState({
    this.status = MushafWordLiveStatus.pending,
    this.recitedAs,
  });

  @override
  bool operator ==(Object other) =>
      other is MushafWordLiveState &&
      other.status == status &&
      other.recitedAs == recitedAs;

  @override
  int get hashCode => Object.hash(status, recitedAs);
}

/// Live highlight payload — updated without rebuilding the whole screen.
class MushafLiveHighlight {
  final Map<int, MushafWordLiveState> wordStates;
  final int? activeWordId;

  const MushafLiveHighlight({
    required this.wordStates,
    this.activeWordId,
  });

  static const empty = MushafLiveHighlight(wordStates: {});

  @override
  bool operator ==(Object other) =>
      other is MushafLiveHighlight &&
      other.activeWordId == activeWordId &&
      _mapsEqual(other.wordStates, wordStates);

  @override
  int get hashCode => Object.hash(activeWordId, wordStates.length);

  static bool _mapsEqual(
    Map<int, MushafWordLiveState> a,
    Map<int, MushafWordLiveState> b,
  ) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}

/// Forward-only matcher: like mobile dictation — words lock in order, never rewind.
class MushafIncrementalMatcher {
  int _refIdx = 0;
  int _processedTransCount = 0;
  List<MushafWord> _refWords = const [];
  List<String> _refNorm = const [];
  final Map<int, MushafWordLiveState> _states = {};
  bool _garbageStreak = false;

  Map<int, MushafWordLiveState> get states => Map.unmodifiable(_states);
  int get refIdx => _refIdx;
  int get processedTransCount => _processedTransCount;

  void reset(List<MushafWord> refWords) {
    _refIdx = 0;
    _processedTransCount = 0;
    _garbageStreak = false;
    _refWords = refWords;
    _refNorm = refWords.map((w) => MushafLiveMatcher.matchKey(w.text)).toList();
    _states.clear();
    for (final w in refWords) {
      _states[w.id] = const MushafWordLiveState();
    }
  }

  int? get activeWordId {
    if (_refIdx >= _refWords.length) return null;
    return _refWords[_refIdx].id;
  }

  /// Rebuild forward progress from a full committed word list (after breath / resync).
  void realignToCommitted(List<String> committedMatchKeys) {
    reset(_refWords);
    if (committedMatchKeys.isNotEmpty) {
      ingestWords(committedMatchKeys);
    }
  }

  /// Commit [newWords] spoken since the last call (append-only).
  bool ingestWords(List<String> newWords) {
    if (newWords.isEmpty) return false;
    var changed = false;
    for (final raw in newWords) {
      final transWord = MushafLiveMatcher.matchKey(raw);
      if (transWord.isEmpty) continue;
      if (_refIdx < _refWords.length) {
        changed = _consumeOne(transWord) || changed;
      }
      _processedTransCount++;
    }
    return changed;
  }

  bool _consumeOne(String transWord) {
    if (transWord.isEmpty || _refIdx >= _refWords.length) return false;

    while (_refIdx < _refWords.length) {
      final refWord = _refNorm[_refIdx];
      final word = _refWords[_refIdx];

      if (MushafLiveMatcher.matches(refWord, transWord)) {
        _states[word.id] = const MushafWordLiveState(
          status: MushafWordLiveStatus.correct,
        );
        _refIdx++;
        _garbageStreak = false;
        return true;
      }

      final refAhead = MushafLiveMatcher.findRefAhead(
        refNorm: _refNorm,
        refIdx: _refIdx,
        transWord: transWord,
      );
      if (refAhead != null) {
        for (var k = _refIdx; k < refAhead; k++) {
          _states[_refWords[k].id] = const MushafWordLiveState(
            status: MushafWordLiveStatus.omitted,
          );
        }
        _states[_refWords[refAhead].id] = const MushafWordLiveState(
          status: MushafWordLiveStatus.correct,
        );
        _refIdx = refAhead + 1;
        _garbageStreak = false;
        return true;
      }

      if (MushafLiveMatcher.isPureSttNoise(refWord, transWord, _refNorm)) {
        _garbageStreak = true;
        return false;
      }

      if (!MushafLiveMatcher.transAppearsInRemainingRef(
        _refNorm,
        _refIdx,
        transWord,
      )) {
        final shared =
            refWord.runes.toSet().intersection(transWord.runes.toSet());
        if (shared.isEmpty) {
          _garbageStreak = true;
          return false;
        }
      }

      if (_garbageStreak &&
          !MushafLiveMatcher.transAppearsInRemainingRef(
            _refNorm,
            _refIdx,
            transWord,
          )) {
        return false;
      }

      _states[word.id] = MushafWordLiveState(
        status: MushafWordLiveStatus.wrong,
        recitedAs: transWord,
      );
      _refIdx++;
      _garbageStreak = false;
      return true;
    }
    return false;
  }

  /// Live preview while the last partial STT word is still being spoken.
  Map<int, MushafWordLiveState> statesWithPartialTail(String? rawTail) {
    final copy = Map<int, MushafWordLiveState>.from(_states);
    if (rawTail == null || rawTail.isEmpty || _refIdx >= _refWords.length) {
      return copy;
    }
    final tail = MushafLiveMatcher.matchKey(rawTail);
    if (tail.isEmpty) return copy;

    final word = _refWords[_refIdx];
    if (copy[word.id]?.status != MushafWordLiveStatus.pending) return copy;

    final refWord = _refNorm[_refIdx];
    if (MushafLiveMatcher.matches(refWord, tail)) {
      copy[word.id] = const MushafWordLiveState(
        status: MushafWordLiveStatus.correct,
      );
    } else if (MushafLiveMatcher.findRefAhead(
              refNorm: _refNorm,
              refIdx: _refIdx,
              transWord: tail,
            ) !=
            null ||
        MushafLiveMatcher.isPureSttNoise(refWord, tail, _refNorm) ||
        (!MushafLiveMatcher.transAppearsInRemainingRef(
              _refNorm,
              _refIdx,
              tail,
            ) &&
            refWord.runes.toSet().intersection(tail.runes.toSet()).isEmpty)) {
      // Preview only — don't flash red for skips, noise, or off-page STT.
    } else {
      copy[word.id] = MushafWordLiveState(
        status: MushafWordLiveStatus.wrong,
        recitedAs: tail,
      );
    }
    return copy;
  }
}

/// Aligns device STT transcript to mushaf page words for live UI.
class MushafLiveMatcher {
  /// Normalized match keys for بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ.
  static const List<String> basmallahMatchKeys = [
    'بسم',
    'الله',
    'الرحمن',
    'الرحيم',
  ];

  static String normalizeArabic(String text) {
    text = text.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED]'), '');
    text = text.replaceAll('\u0640', '');
    text = text.replaceAll('\u0671', '\u0627');
    text = text.replaceAll(RegExp(r'[\u0625\u0623\u0622\u0627]'), '\u0627');
    text = text.replaceAll('\u0624', '\u0648');
    text = text.replaceAll('\u0626', '\u064A');
    text = text.replaceAll('\u0649', '\u064A');
    text = text.replaceAll('\u0629', '\u0647');
    text = text.replaceAll('\u0621', '');
    text = text.replaceAll(RegExp(r'[^\u0621-\u064A\s]'), '');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool isSimilar(String a, String b) {
    if (a == b) return true;
    if (a.isEmpty || b.isEmpty) return false;

    final short = a.length <= 3 || b.length <= 3;
    if (short && (a.contains(b) || b.contains(a))) return true;

    final setA = a.runes.toSet();
    final setB = b.runes.toSet();
    final union = setA.union(setB);
    if (union.isEmpty) return false;
    if (setA.intersection(setB).length / union.length > 0.55) return true;

    final maxLen = a.length > b.length ? a.length : b.length;
    var commonPrefix = 0;
    for (var i = 0; i < maxLen && i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) break;
      commonPrefix++;
    }
    return commonPrefix >= 2 && commonPrefix / maxLen >= 0.5;
  }

  /// Canonical form for word matching (diacritics + hamza + final-ya variants).
  static String matchKey(String text) {
    var key = normalizeArabic(text);
    if (key.length >= 3 && key.endsWith('\u064A')) {
      key = key.substring(0, key.length - 1);
    }
    return key;
  }

  /// STT-tolerant match: accepts orthography drift and a dropped final letter,
  /// but rejects real misreads (extra letters, multiple consonant swaps).
  static bool matches(String ref, String trans) {
    if (ref == trans) return true;
    if (ref.isEmpty || trans.isEmpty) return false;
    if (_isFinalLetterVariant(ref, trans)) return true;

    final lenDiff = (ref.length - trans.length).abs();
    if (lenDiff > 1) return false;
    if (lenDiff == 1) return false;

    final mismatches = _mismatchCount(ref, trans);
    if (mismatches <= 1) return isSimilar(ref, trans);
    return false;
  }

  static bool _isFinalLetterVariant(String a, String b) {
    if (a.isEmpty || b.isEmpty || a == b) return false;
    final shorter = a.length < b.length ? a : b;
    final longer = a.length < b.length ? b : a;
    final diff = longer.length - shorter.length;
    if (diff <= 0 || diff > 1) return false;
    return longer.startsWith(shorter);
  }

  static int _mismatchCount(String a, String b) {
    final maxLen = a.length > b.length ? a.length : b.length;
    var count = 0;
    for (var i = 0; i < maxLen; i++) {
      final ca = i < a.length ? a[i] : '';
      final cb = i < b.length ? b[i] : '';
      if (ca != cb) count++;
    }
    return count;
  }

  static bool matchesLoosely(String ref, String trans) =>
      ref == trans || isSimilar(ref, trans);

  /// Page words used for live matching — Basmallah is never scored.
  static List<MushafWord> refWordsForMatching(
    List<MushafWord> pageWords, {
    bool pageHasDecorativeBasmallah = false,
  }) {
    if (pageWords.isEmpty) return pageWords;

    var words = pageWords;

    // Al-Fatiha ayah 1 is only the Basmallah — skip it entirely.
    if (words.first.surahNumber == 1 && words.first.ayahNumber == 1) {
      words = words
          .where((w) => !(w.surahNumber == 1 && w.ayahNumber == 1))
          .toList();
    }

    if (pageHasDecorativeBasmallah) {
      words = _dropLeadingBasmallahRefWords(words);
    }

    return words;
  }

  static List<MushafWord> _dropLeadingBasmallahRefWords(
    List<MushafWord> words,
  ) {
    var skip = 0;
    for (final expected in basmallahMatchKeys) {
      if (skip >= words.length) break;
      if (matches(expected, matchKey(words[skip].text))) {
        skip++;
      } else {
        break;
      }
    }
    if (skip == 0) return words;
    return words.sublist(skip);
  }

  static List<String> stripLeadingBasmallahWordKeys(List<String> matchKeys) {
    if (matchKeys.isEmpty) return matchKeys;
    var skip = 0;
    for (final expected in basmallahMatchKeys) {
      if (skip >= matchKeys.length) break;
      if (matches(expected, matchKeys[skip])) {
        skip++;
      } else {
        break;
      }
    }
    if (skip == 0) return matchKeys;
    return matchKeys.sublist(skip);
  }

  static String stripLeadingBasmallahFromTranscript(String transcript) {
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) return trimmed;

    final rawWords =
        trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (rawWords.isEmpty) return trimmed;

    final matchKeys = rawWords.map(matchKey).toList();
    final strippedKeys = stripLeadingBasmallahWordKeys(matchKeys);
    if (strippedKeys.length == matchKeys.length) return trimmed;

    final skip = matchKeys.length - strippedKeys.length;
    return rawWords.sublist(skip).join(' ');
  }

  static bool isLikelyMisread(String refWord, String transWord) {
    if (isSimilar(refWord, transWord)) return true;
    final setA = refWord.runes.toSet();
    final setB = transWord.runes.toSet();
    final shared = setA.intersection(setB);
    if (shared.isEmpty) return false;
    final union = setA.union(setB);
    final ratio = shared.length / union.length;
    final minLen =
        refWord.length < transWord.length ? refWord.length : transWord.length;
    if (minLen <= 3) return ratio >= 0.25;
    return ratio >= 0.35;
  }

  static int? findRefAhead({
    required List<String> refNorm,
    required int refIdx,
    required String transWord,
  }) {
    for (var k = refIdx + 1; k < refNorm.length; k++) {
      if (matches(refNorm[k], transWord)) return k;
    }
    return null;
  }

  static bool transAppearsInRemainingRef(
    List<String> refNorm,
    int refIdx,
    String transWord,
  ) {
    for (var k = refIdx; k < refNorm.length; k++) {
      if (matches(refNorm[k], transWord)) return true;
    }
    return false;
  }

  /// Ignore long STT hallucinations that do not appear anywhere on the page.
  static bool isPureSttNoise(
    String refWord,
    String transWord,
    List<String> refNorm,
  ) {
    if (transWord.length <= 4) return false;
    if (refNorm.any((r) => r == transWord || isSimilar(r, transWord))) {
      return false;
    }
    if (isLikelyMisread(refWord, transWord)) return false;
    return true;
  }

  static Map<String, dynamic> mergeLiveIntoServerResult({
    required Map<String, dynamic> server,
    required Map<String, dynamic> local,
  }) {
    // Hafs / server alignment is authoritative — local STT can false-flag words.
    return Map<String, dynamic>.from(server);
  }

  /// Rebuild mushaf highlights from server analysis (Hafs transcript preferred).
  static Map<int, MushafWordLiveState> wordStatesFromAnalysis({
    required List<MushafWord> refWords,
    required Map<String, dynamic> result,
  }) {
    final transcript = (result['transcribed_text'] ?? result['transcribedText'])
            ?.toString()
            .trim() ??
        '';
    if (transcript.isNotEmpty) {
      final cleaned =
          stripLeadingBasmallahFromTranscript(transcript);
      final matcher = MushafIncrementalMatcher()..reset(refWords);
      matcher.ingestWords(allWordsFromTranscript(cleaned));
      return Map<int, MushafWordLiveState>.from(matcher.states);
    }
    return _wordStatesFromServerErrors(refWords, result);
  }

  static Map<int, MushafWordLiveState> _wordStatesFromServerErrors(
    List<MushafWord> refWords,
    Map<String, dynamic> result,
  ) {
    final states = {
      for (final w in refWords) w.id: const MushafWordLiveState(),
    };
    final errors = (result['errors'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    if (errors.isEmpty) return states;

    final errorByIndex = <int, Map<String, dynamic>>{};
    for (final err in errors) {
      final idx = (err['wordIndex'] ?? err['word_index'] as num?)?.toInt();
      if (idx == null) continue;
      errorByIndex[idx] = err;
    }

    final total = (result['total_words'] as num?)?.toInt() ?? refWords.length;
    final limit = total.clamp(0, refWords.length);
    for (var i = 0; i < limit; i++) {
      final w = refWords[i];
      final err = errorByIndex[i];
      if (err == null) {
        states[w.id] = const MushafWordLiveState(
          status: MushafWordLiveStatus.correct,
        );
        continue;
      }
      final type = err['type']?.toString() ?? '';
      if (type == 'omission') {
        states[w.id] = const MushafWordLiveState(
          status: MushafWordLiveStatus.omitted,
        );
      } else if (type != 'addition') {
        states[w.id] = MushafWordLiveState(
          status: MushafWordLiveStatus.wrong,
          recitedAs: (err['recitedWord'] ?? err['recited_word'] ?? '')
              .toString(),
        );
      }
    }
    return states;
  }

  /// Split transcript into committed words (trailing partial word excluded).
  static List<String> committedWordsFromTranscript(String transcript) {
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed.endsWith(' ')) {
      return trimmed
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map(MushafLiveMatcher.matchKey)
          .toList();
    }
    final parts = trimmed.split(' ').where((w) => w.isNotEmpty).toList();
    if (parts.length <= 1) return const [];
    return parts.sublist(0, parts.length - 1).map(matchKey).toList();
  }

  static List<String> allWordsFromTranscript(String transcript) {
    return transcript
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map(matchKey)
        .toList();
  }

  static String mergeTranscriptSegment(String base, String segment) {
    segment = segment.trim();
    if (segment.isEmpty) return base;
    if (base.isEmpty) return segment;
    if (segment.startsWith(base)) return segment;
    if (base.startsWith(segment)) return base;

    final baseWords =
        base.split(' ').where((w) => w.isNotEmpty).toList(growable: false);
    final segWords =
        segment.split(' ').where((w) => w.isNotEmpty).toList(growable: false);
    if (baseWords.isEmpty) return segment;
    if (segWords.isEmpty) return base;

    final maxOverlap = baseWords.length < segWords.length
        ? baseWords.length
        : segWords.length;
    for (var overlap = maxOverlap; overlap > 0; overlap--) {
      var ok = true;
      for (var i = 0; i < overlap; i++) {
        final bw = matchKey(baseWords[baseWords.length - overlap + i]);
        final sw = matchKey(segWords[i]);
        if (bw != sw && !matches(bw, sw)) {
          ok = false;
          break;
        }
      }
      if (ok) {
        final tail = segWords.sublist(overlap).join(' ');
        if (tail.isEmpty) return base;
        return '$base $tail'.trim();
      }
    }
    return '$base $segment'.trim();
  }

  static Map<String, dynamic> buildLocalSessionResult({
    required List<MushafWord> refWords,
    required Map<int, MushafWordLiveState> states,
  }) {
    final errors = <Map<String, dynamic>>[];
    var correct = 0;

    for (final w in refWords) {
      final state = states[w.id];
      if (state == null || state.status == MushafWordLiveStatus.pending) {
        continue;
      }
      if (state.status == MushafWordLiveStatus.correct) {
        correct++;
      } else if (state.status == MushafWordLiveStatus.wrong) {
        errors.add({
          'type': 'substitution',
          'expectedWord': w.text,
          'recitedWord': state.recitedAs ?? '',
        });
      } else if (state.status == MushafWordLiveStatus.omitted) {
        errors.add({
          'type': 'omission',
          'expectedWord': w.text,
          'recitedWord': '',
        });
      }
    }

    final total = refWords.length;
    return {
      'similarity_score': total > 0 ? (correct / total * 100) : 0.0,
      'errors': errors,
      'harakatMistakes': 0,
      'harakatChecked': 0,
      'evaluated_words': states.values
          .where((s) => s.status != MushafWordLiveStatus.pending)
          .length,
      'total_words': total,
      'source': 'local',
    };
  }
}
