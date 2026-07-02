import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/constants.dart';

class TafsirService extends ChangeNotifier {
  final Map<String, String> _cache = {};

  /// Fetches tafsir text for [surahNumber]:[ayahNumber], using in-memory cache.
  Future<String> getAyahTafsir(int surahNumber, int ayahNumber) async {
    final key = '$surahNumber:$ayahNumber';
    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }

    final response = await http.get(
      Uri.parse(
        '${AppConstants.quranApiBaseUrl}/ayah/$surahNumber:$ayahNumber/${AppConstants.tafsirEdition}',
      ),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load tafsir: ${response.statusCode}');
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>?;
    final text = (data?['text'] as String?)?.trim();

    if (text == null || text.isEmpty) {
      throw Exception('Missing tafsir text');
    }

    _cache[key] = text;
    return text;
  }

  void clearCache() {
    _cache.clear();
    notifyListeners();
  }
}
