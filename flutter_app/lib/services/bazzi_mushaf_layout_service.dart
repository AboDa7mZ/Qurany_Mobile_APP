import '../config/mushaf_pages.dart';
import '../models/mushaf_layout.dart';
import '../models/verse.dart';
import 'al_bazzi_service.dart';

/// Builds mushaf-style paginated layout for Al-Bazzi Surah Al-Baqara
/// so the reader matches the Hafs mushaf UI (page swipe, justified lines).
class BazziMushafLayoutService {
  static const int surahNumber = 2;
  static const double _referenceFontSize = 19.0;
  static const double _referenceLineWidth = 340.0;

  List<MushafPage>? _cachedPages;

  Future<List<MushafPage>> loadPages() async {
    if (_cachedPages != null) return _cachedPages!;
    final verses = await AlBazziService().getBaqaraVerses();
    _cachedPages = _buildPages(verses);
    return _cachedPages!;
  }

  List<MushafPage> _buildPages(List<Verse> verses) {
    final ayahLines = _packAyahLines(verses);
    final pages = <MushafPage>[];
    var pageNumber = 1;
    var lineIndex = 0;

    while (lineIndex < ayahLines.length || pageNumber == 1) {
      final pageLines = <MushafLine>[];
      var lineOnPage = 1;

      if (pageNumber == 1) {
        pageLines.add(MushafLine(
          lineNumber: lineOnPage++,
          type: MushafLineType.surahName,
          surahNumber: surahNumber,
        ));
        pageLines.add(MushafLine(
          lineNumber: lineOnPage++,
          type: MushafLineType.basmallah,
        ));
      }

      while (lineOnPage <= MushafPageIndex.linesPerPage &&
          lineIndex < ayahLines.length) {
        pageLines.add(MushafLine(
          lineNumber: lineOnPage++,
          type: MushafLineType.ayah,
          ayahGroups: ayahLines[lineIndex],
        ));
        lineIndex++;
      }

      pages.add(MushafPage(pageNumber: pageNumber, lines: pageLines));
      pageNumber++;
      if (lineIndex >= ayahLines.length && pageNumber > 1) break;
    }

    return pages;
  }

  List<List<MushafAyahGroup>> _packAyahLines(List<Verse> verses) {
    final lines = <List<MushafAyahGroup>>[];
    var currentGroups = <MushafAyahGroup>[];
    var currentWidth = 0.0;
    var wordId = 1;

    void flushLine() {
      if (currentGroups.isNotEmpty) {
        lines.add(List.from(currentGroups));
        currentGroups = [];
        currentWidth = 0.0;
      }
    }

    for (final verse in verses) {
      final verseKey = '$surahNumber:${verse.verseNumber}';
      final rawWords =
          verse.text.split(' ').where((w) => w.isNotEmpty).toList();
      var groupWords = <MushafWord>[];

      void flushGroup() {
        if (groupWords.isEmpty) return;
        currentGroups.add(
          MushafAyahGroup(verseKey: verseKey, words: List.from(groupWords)),
        );
        groupWords = [];
      }

      for (var i = 0; i < rawWords.length; i++) {
        final w = rawWords[i];
        final wordWidth = _estimateWordWidth(w);
        if (currentWidth + wordWidth > _referenceLineWidth && currentGroups.isNotEmpty) {
          flushGroup();
          flushLine();
        }

        if (groupWords.isEmpty && currentWidth + wordWidth > _referenceLineWidth) {
          flushLine();
        }

        groupWords.add(MushafWord(
          id: wordId++,
          text: w,
          verseKey: verseKey,
          positionInVerse: i + 1,
          isAyahMarker: false,
        ));
        currentWidth += wordWidth;
      }

      final markerWidth = _estimateWordWidth('${verse.verseNumber}', isMarker: true);
      if (currentWidth + markerWidth > _referenceLineWidth && groupWords.isNotEmpty) {
        flushGroup();
        flushLine();
      }

      groupWords.add(MushafWord(
        id: wordId++,
        text: '${verse.verseNumber}',
        verseKey: verseKey,
        positionInVerse: rawWords.length + 1,
        isAyahMarker: true,
      ));
      currentWidth += markerWidth;
      flushGroup();
    }

    flushLine();
    return lines;
  }

  double _estimateWordWidth(String word, {bool isMarker = false}) {
    if (isMarker) return _referenceFontSize * 1.4 + 6;
    return _referenceFontSize * 0.48 * word.length + 7;
  }
}
