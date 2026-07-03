import 'dart:io';

import 'package:flutter/foundation.dart';

class AppConstants {
  // Quran API (public)
  static const String quranApiBaseUrl = 'https://api.alquran.cloud/v1';

  /// English translation edition for random verse / ayah lookups.
  /// See https://api.alquran.cloud/v1/edition/type/translation
  static const String quranEnglishEdition = 'en.sahih';

  /// Arabic tafsir edition (Jalalayn). See https://api.alquran.cloud/v1/edition/type/tafsir
  static const String tafsirEdition = 'ar.jalalayn';
  static const String tafsirEditionName = 'تفسير الجلالين';

  // Prayer times (Aladhan API)
  static const String aladhanApiBaseUrl = 'https://api.aladhan.com/v1';
  static const String defaultPrayerCity = 'Cairo';
  static const String defaultPrayerCountry = 'Egypt';

  /// Egyptian General Authority of Survey (appropriate for Cairo)
  static const int aladhanCalculationMethod = 5;

  // Recitation analysis backend (FastAPI + faster-whisper).
  // Resolution order:
  //   1. Address saved by the user in Settings (works on real devices where
  //      the backend runs on a LAN laptop whose IP changes per network)
  //   2. Build-time override: --dart-define=QURANY_API_BASE=http://<host>:8000
  //   3. Platform default (10.0.2.2 only resolves inside the Android
  //      emulator; on a physical phone it points at nothing)
  static const String recitationApiPrefsKey = 'recitation_api_base_url';

  /// Set at startup (main.dart) from SharedPreferences and whenever the user
  /// saves a new address in Settings.
  static String? recitationApiUserOverride;

  static String get recitationApiDefaultUrl {
    const override = String.fromEnvironment('QURANY_API_BASE');
    if (override.isNotEmpty) return override;
    if (kIsWeb) return 'http://localhost:8000';
    if (!Platform.isAndroid) return 'http://localhost:8000';
    return 'http://10.0.2.2:8000';
  }

  static String get recitationApiBaseUrl {
    final user = recitationApiUserOverride?.trim();
    if (user != null && user.isNotEmpty) return user;
    return recitationApiDefaultUrl;
  }

  // Surahs supported by the recitation backend (MVP scope).
  static const List<int> serverSupportedSurahs = [78, 2];

  // Audio settings
  static const int audioSampleRate = 16000;
  static const int audioChunkDurationMs = 500;

  // Recitation settings
  static const int correctionTimerSeconds = 10;
  static const double minSimilarityThreshold = 0.85;

  // App info
  static const String appName = 'Qurany';
  static const String appVersion = '1.0.0';
  static const String appDescription =
      'AI-Powered Quran Recitation Assistant';

  // Surah names in Arabic
  static const List<String> surahNames = [
    'الفاتحة', 'البقرة', 'آل عمران', 'النساء', 'المائدة',
    'الأنعام', 'الأعراف', 'الأنفال', 'التوبة', 'يونس',
    'هود', 'يوسف', 'الرعد', 'إبراهيم', 'الحجر',
    'النحل', 'الإسراء', 'الكهف', 'مريم', 'طه',
    'الأنبياء', 'الحج', 'المؤمنون', 'النور', 'الفرقان',
    'الشعراء', 'النمل', 'القصص', 'العنكبوت', 'الروم',
    'لقمان', 'السجدة', 'الأحزاب', 'سبأ', 'فاطر',
    'يس', 'الصافات', 'ص', 'الزمر', 'غافر',
    'فصلت', 'الشورى', 'الزخرف', 'الدخان', 'الجاثية',
    'الأحقاف', 'محمد', 'الفتح', 'الحجرات', 'ق',
    'الذاريات', 'الطور', 'النجم', 'القمر', 'الرحمن',
    'الواقعة', 'الحديد', 'المجادلة', 'الحشر', 'الممتحنة',
    'الصف', 'الجمعة', 'المنافقون', 'التغابن', 'الطلاق',
    'التحريم', 'الملك', 'القلم', 'الحاقة', 'المعارج',
    'نوح', 'الجن', 'المزمل', 'المدثر', 'القيامة',
    'الإنسان', 'المرسلات', 'النبأ', 'النازعات', 'عبس',
    'التكوير', 'الانفطار', 'المطففين', 'الانشقاق', 'البروج',
    'الطارق', 'الأعلى', 'الغاشية', 'الفجر', 'البلد',
    'الشمس', 'الليل', 'الضحى', 'الشرح', 'التين',
    'العلق', 'القدر', 'البينة', 'الزلزلة', 'العاديات',
    'القارعة', 'التكاثر', 'العصر', 'الهمزة', 'الفيل',
    'قريش', 'الماعون', 'الكوثر', 'الكافرون', 'النصر',
    'المسد', 'الإخلاص', 'الفلق', 'الناس',
  ];

  // Number of verses per surah
  static const List<int> surahVerseCount = [
    7, 286, 200, 176, 120, 165, 206, 75, 129, 109,
    123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
    112, 78, 118, 64, 77, 227, 93, 88, 69, 60,
    34, 30, 73, 54, 45, 83, 182, 88, 75, 85,
    54, 53, 89, 59, 37, 35, 38, 29, 18, 45,
    60, 49, 62, 55, 78, 96, 29, 22, 24, 13,
    14, 11, 11, 18, 12, 12, 30, 52, 52, 44,
    28, 28, 20, 56, 40, 31, 50, 40, 46, 42,
    29, 19, 36, 25, 22, 17, 19, 26, 30, 20,
    15, 21, 11, 8, 8, 19, 5, 8, 8, 11,
    11, 8, 3, 9, 5, 4, 7, 3, 6, 3,
    5, 4, 5, 6,
  ];

  // Revelation types
  static const List<String> surahRevelationType = [
    'مكية', 'مدنية', 'مدنية', 'مدنية', 'مدنية',
    'مكية', 'مكية', 'مدنية', 'مدنية', 'مكية',
    'مكية', 'مكية', 'مدنية', 'مكية', 'مكية',
    'مكية', 'مكية', 'مكية', 'مكية', 'مكية',
    'مكية', 'مدنية', 'مكية', 'مدنية', 'مكية',
    'مكية', 'مكية', 'مكية', 'مكية', 'مكية',
    'مكية', 'مكية', 'مدنية', 'مكية', 'مكية',
    'مكية', 'مكية', 'مكية', 'مكية', 'مكية',
    'مكية', 'مكية', 'مكية', 'مكية', 'مكية',
    'مكية', 'مدنية', 'مدنية', 'مدنية', 'مكية',
    'مكية', 'مكية', 'مكية', 'مكية', 'مدنية',
    'مكية', 'مدنية', 'مدنية', 'مدنية', 'مدنية',
    'مدنية', 'مدنية', 'مدنية', 'مدنية', 'مدنية',
    'مدنية', 'مكية', 'مكية', 'مكية', 'مكية',
    'مكية', 'مكية', 'مكية', 'مكية', 'مكية',
    'مدنية', 'مكية', 'مكية', 'مكية', 'مكية',
    'مكية', 'مكية', 'مكية', 'مكية', 'مكية',
    'مكية', 'مكية', 'مكية', 'مكية', 'مكية',
    'مكية', 'مكية', 'مكية', 'مكية', 'مكية',
    'مكية', 'مكية', 'مدنية', 'مدنية', 'مكية',
    'مكية', 'مكية', 'مكية', 'مكية', 'مكية',
    'مكية', 'مكية', 'مكية', 'مكية', 'مدنية',
    'مكية', 'مكية', 'مكية', 'مكية',
  ];
}
