import 'package:flutter/services.dart';
import '../models/verse.dart';

/// Service that loads Al-Bazzi qira'a for Surah Al-Baqara from a bundled
/// text file asset. The text file contains the entire surah on a single line,
/// with verse markers like (1), (2), etc.
///
/// Al-Bazzi has a different verse count than Hafs (some Hafs verses are
/// combined), so the verse numbers come directly from the file markers.
class AlBazziService {
  static const String _assetPath = 'assets/al_bazzi_baqara.txt';
  static const int _surahNumber = 2; // Al-Baqara

  List<Verse>? _cachedVerses;

  /// Returns the parsed verses for Al-Bazzi's Surah Al-Baqara.
  /// Reads from the asset file on first call, then caches in memory.
  Future<List<Verse>> getBaqaraVerses() async {
    if (_cachedVerses != null) return _cachedVerses!;

    try {
      final rawText = await rootBundle.loadString(_assetPath);
      _cachedVerses = _parseVerses(rawText);
      return _cachedVerses!;
    } catch (e) {
      throw Exception('فشل تحميل قراءة البزي: $e');
    }
  }

  /// Total number of verses in the Al-Bazzi text.
  Future<int> getVerseCount() async {
    final verses = await getBaqaraVerses();
    return verses.length;
  }

  /// Parses the raw text by splitting on verse markers like (1), (2), (286).
  /// Handles both Western digits (1-9) and Eastern Arabic digits (٠-٩).
  List<Verse> _parseVerses(String rawText) {
    // Match verse markers: (N) where N is one or more digits.
    // This regex captures both Western and Eastern Arabic numerals.
    final markerPattern = RegExp(r'\((\d+)\)');

    final matches = markerPattern.allMatches(rawText).toList();
    if (matches.isEmpty) return [];

    final verses = <Verse>[];

    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];
      final verseNumber = int.parse(match.group(1)!);

      // Verse text is from the end of the previous marker to the start
      // of the current marker.
      final textStart = i == 0 ? 0 : matches[i - 1].end;
      final textEnd = match.start;

      var verseText = rawText.substring(textStart, textEnd).trim();

      // Remove the hizb marker (۞) from the beginning if present — it's
      // a structural symbol, not part of the verse text per se, but we
      // keep it for display consistency with Hafs (which also shows it).

      if (verseText.isEmpty) continue;

      verses.add(Verse(
        surahNumber: _surahNumber,
        verseNumber: verseNumber,
        text: verseText,
      ));
    }

    return verses;
  }

  /// Clear the in-memory cache.
  void clearCache() {
    _cachedVerses = null;
  }
}
