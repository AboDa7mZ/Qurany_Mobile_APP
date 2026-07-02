class Verse {
  final int surahNumber;
  final int verseNumber;
  final int globalNumber; // Global ayah number (1-6236) for audio URLs
  final int? pageNumber; // Page number
  final String text; // Uthmani script with diacritics
  final String textSimple; // Without diacritics

  const Verse({
    required this.surahNumber,
    required this.verseNumber,
    this.globalNumber = 0,
    this.pageNumber,
    required this.text,
    this.textSimple = '',
  });

  /// Husary audio URL for this verse (EveryAyah API is more reliable)
  String get husaryAudioUrl {
    final s = surahNumber.toString().padLeft(3, '0');
    final v = verseNumber.toString().padLeft(3, '0');
    return 'https://everyayah.com/data/Husary_128kbps/$s$v.mp3';
  }

  factory Verse.fromJson(Map<String, dynamic> json) {
    return Verse(
      surahNumber: json['surah']?['number'] ?? json['surahNumber'] ?? 0,
      verseNumber: json['numberInSurah'] ?? json['verseNumber'] ?? 0,
      globalNumber: json['number'] ?? json['globalNumber'] ?? 0,
      pageNumber: json['page'] ?? json['pageNumber'],
      text: json['text'] ?? '',
      textSimple: json['textSimple'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'surahNumber': surahNumber,
        'verseNumber': verseNumber,
        'globalNumber': globalNumber,
        'pageNumber': pageNumber,
        'text': text,
        'textSimple': textSimple,
      };
}
