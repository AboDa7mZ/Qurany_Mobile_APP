import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../models/prayer_times.dart';

class PrayerTimesService extends ChangeNotifier {
  PrayerTimesService(this._prefs);

  final SharedPreferences _prefs;

  PrayerTimesDay? _today;
  bool _isLoading = false;
  String? _error;

  PrayerTimesDay? get today => _today;
  bool get isLoading => _isLoading;
  String? get error => _error;

  String get city =>
      _prefs.getString('prayer_city') ?? AppConstants.defaultPrayerCity;
  String get country =>
      _prefs.getString('prayer_country') ?? AppConstants.defaultPrayerCountry;

  Future<void> loadPrayerTimes({bool force = false}) async {
    if (_isLoading) return;
    if (!force && _today != null && _isSameDay(_today!.fetchedAt, DateTime.now())) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final uri = Uri.parse(
        '${AppConstants.aladhanApiBaseUrl}/timingsByCity'
        '?city=${Uri.encodeComponent(city)}'
        '&country=${Uri.encodeComponent(country)}'
        '&method=${AppConstants.aladhanCalculationMethod}',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('Prayer times request failed (${response.statusCode})');
      }

      final body = json.decode(response.body) as Map<String, dynamic>;
      if (body['code'] != 200) {
        throw Exception('Aladhan API error');
      }

      final data = body['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('Missing prayer times data');
      }

      final timings = data['timings'] as Map<String, dynamic>?;
      final meta = data['meta'] as Map<String, dynamic>? ?? {};
      if (timings == null) {
        throw Exception('Missing timings');
      }

      final now = DateTime.now();
      final entries = <PrayerTimeEntry>[];
      for (final name in PrayerName.displayOrder) {
        final raw = timings[name.apiKey] as String?;
        if (raw == null) continue;
        entries.add(
          PrayerTimeEntry(
            name: name,
            time: _parsePrayerTime(raw, now),
          ),
        );
      }

      if (entries.isEmpty) {
        throw Exception('No prayer times returned');
      }

      _today = PrayerTimesDay(
        city: city,
        country: country,
        timezone: meta['timezone'] as String? ?? '',
        entries: entries,
        fetchedAt: now,
      );
    } catch (e) {
      _error = 'Could not load prayer times. Check your connection.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateLocation({
    required String city,
    required String country,
  }) async {
    await _prefs.setString('prayer_city', city);
    await _prefs.setString('prayer_country', country);
    _today = null;
    await loadPrayerTimes(force: true);
  }

  DateTime _parsePrayerTime(String raw, DateTime referenceDay) {
    final clean = raw.split(' ').first.trim();
    final parts = clean.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return DateTime(
      referenceDay.year,
      referenceDay.month,
      referenceDay.day,
      hour,
      minute,
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
