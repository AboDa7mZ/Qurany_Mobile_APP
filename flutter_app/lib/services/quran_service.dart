import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/verse.dart';
import '../config/constants.dart';

class QuranService extends ChangeNotifier {
  static const Duration _httpTimeout = Duration(seconds: 15);

  final Map<int, List<Verse>> _surahCache = {};
  final _random = Random();
  bool _isLoading = false;
  String? _error;

  Verse? _verseOfTheDay;
  bool _verseOfTheDayLoading = false;
  bool _fetchingVerseTranslation = false;
  String? _verseOfTheDayError;

  bool get isLoading => _isLoading;
  String? get error => _error;
  Verse? get verseOfTheDay => _verseOfTheDay;
  bool get verseOfTheDayLoading => _verseOfTheDayLoading;
  String? get verseOfTheDayError => _verseOfTheDayError;

  /// Fetch verses for a specific Surah from the Quran API
  Future<List<Verse>> getSurahVerses(int surahNumber) async {
    // Return from cache if available
    if (_surahCache.containsKey(surahNumber)) {
      return _surahCache[surahNumber]!;
    }

    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      final response = await http
          .get(
            Uri.parse(
              '${AppConstants.quranApiBaseUrl}/surah/$surahNumber/ar.uthmani',
            ),
          )
          .timeout(_httpTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final ayahs = data['data']['ayahs'] as List;
        final verses = ayahs.map((a) {
          final map = Map<String, dynamic>.from(a);
          map['surahNumber'] = surahNumber;
          return Verse.fromJson(map);
        }).toList();

        _surahCache[surahNumber] = verses;
        _isLoading = false;
        _safeNotify();
        return verses;
      } else {
        throw Exception('Failed to load Surah: ${response.statusCode}');
      }
    } catch (e) {
      _error = 'فشل تحميل السورة. تأكد من اتصالك بالإنترنت.';
      _isLoading = false;
      _safeNotify();
      return [];
    }
  }

  /// Notify listeners safely, deferring if called during build phase
  void _safeNotify() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  /// Pick a random verse from the Quran API (fresh on each app open).
  Future<void> loadRandomVerse() async {
    if (_verseOfTheDayLoading) return;

    _verseOfTheDayLoading = true;
    _verseOfTheDayError = null;
    _verseOfTheDay = null;
    notifyListeners();

    try {
      const totalAyahs = 6236;
      final ayahNumber = _random.nextInt(totalAyahs) + 1;
      _verseOfTheDay = await _fetchVerseByGlobalNumber(ayahNumber);
    } catch (e) {
      _verseOfTheDayError = 'تعذر تحميل آية اليوم. تأكد من اتصالك بالإنترنت.';
    } finally {
      _verseOfTheDayLoading = false;
      notifyListeners();
    }
  }

  /// Ensures the current verse-of-the-day has an English translation.
  /// If no verse is loaded yet, loads a random one. If a verse exists but
  /// was cached before translations were added (e.g. after hot reload), fetches
  /// English for that same ayah without picking a new random verse.
  Future<void> ensureVerseOfTheDayWithTranslation() async {
    if (_verseOfTheDayLoading || _fetchingVerseTranslation) return;

    final current = _verseOfTheDay;
    if (current != null &&
        current.englishTranslation != null &&
        current.englishTranslation!.isNotEmpty) {
      return;
    }

    if (current == null) {
      await loadRandomVerse();
      return;
    }

    _fetchingVerseTranslation = true;
    try {
      final globalNumber =
          current.globalNumber > 0 ? current.globalNumber : null;
      if (globalNumber == null) {
        await loadRandomVerse();
        return;
      }

      final english = await _fetchEnglishTranslation(globalNumber);
      if (english == null || english.isEmpty) return;

      _verseOfTheDay = Verse(
        surahNumber: current.surahNumber,
        verseNumber: current.verseNumber,
        globalNumber: current.globalNumber,
        pageNumber: current.pageNumber,
        text: current.text,
        textSimple: current.textSimple,
        englishTranslation: english,
      );
      notifyListeners();
    } catch (_) {
      // Keep showing Arabic; user can tap retry for a fresh random ayah.
    } finally {
      _fetchingVerseTranslation = false;
    }
  }

  Future<Verse> _fetchVerseByGlobalNumber(int ayahNumber) async {
    final base = AppConstants.quranApiBaseUrl;

    final responses = await Future.wait([
      http.get(Uri.parse('$base/ayah/$ayahNumber/ar.uthmani')),
      http.get(
        Uri.parse(
          '$base/ayah/$ayahNumber/${AppConstants.quranEnglishEdition}',
        ),
      ),
    ]);

    final arabicResponse = responses[0];
    final englishResponse = responses[1];

    if (arabicResponse.statusCode != 200) {
      throw Exception('Failed to load ayah: ${arabicResponse.statusCode}');
    }

    final body = json.decode(arabicResponse.body) as Map<String, dynamic>;
    final ayah = body['data'] as Map<String, dynamic>?;
    if (ayah == null) {
      throw Exception('Missing ayah data');
    }

    final surah = ayah['surah'] as Map<String, dynamic>? ?? {};
    final text = (ayah['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) {
      throw Exception('Empty ayah text');
    }

    String? englishTranslation;
    if (englishResponse.statusCode == 200) {
      englishTranslation = _parseEnglishText(englishResponse.body);
    }

    return Verse(
      surahNumber: surah['number'] as int? ?? 0,
      verseNumber: ayah['numberInSurah'] as int? ?? 0,
      globalNumber: ayah['number'] as int? ?? ayahNumber,
      pageNumber: ayah['page'] as int?,
      text: text,
      englishTranslation: englishTranslation,
    );
  }

  Future<String?> _fetchEnglishTranslation(int globalAyahNumber) async {
    final response = await http.get(
      Uri.parse(
        '${AppConstants.quranApiBaseUrl}/ayah/$globalAyahNumber/${AppConstants.quranEnglishEdition}',
      ),
    );
    if (response.statusCode != 200) return null;
    return _parseEnglishText(response.body);
  }

  String? _parseEnglishText(String responseBody) {
    final englishBody = json.decode(responseBody) as Map<String, dynamic>;
    final englishAyah = englishBody['data'] as Map<String, dynamic>?;
    final text = (englishAyah?['text'] as String?)?.trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  String surahNameFor(int surahNumber) {
    if (surahNumber < 1 || surahNumber > AppConstants.surahNames.length) {
      return '';
    }
    return AppConstants.surahNames[surahNumber - 1];
  }

  /// Search across the Quran
  Future<List<Map<String, dynamic>>> searchQuran(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final response = await http
          .get(
            Uri.parse(
              '${AppConstants.quranApiBaseUrl}/search/$query/all/ar',
            ),
          )
          .timeout(_httpTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final matches = data['data']['matches'] as List? ?? [];
        return matches.map((m) {
          return {
            'text': m['text'] ?? '',
            'surahNumber': m['surah']?['number'] ?? 0,
            'surahName': m['surah']?['name'] ?? '',
            'verseNumber': m['numberInSurah'] ?? 0,
          };
        }).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get the full text of a surah (all verses concatenated) for recitation comparison
  Future<String> getSurahFullText(int surahNumber) async {
    final verses = await getSurahVerses(surahNumber);
    return verses.map((v) => v.text).join(' ');
  }

  /// Clear cache
  void clearCache() {
    _surahCache.clear();
    notifyListeners();
  }
}
