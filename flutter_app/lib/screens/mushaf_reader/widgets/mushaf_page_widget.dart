import 'package:flutter/material.dart';
import '../../../config/constants.dart';
import '../../../config/mushaf_pages.dart';
import '../../../config/theme.dart';
import '../../../models/mushaf_layout.dart';
import '../../../services/mushaf_live_matcher.dart';

const String _basmallahText = 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ';

/// Fixed horizontal padding (each side) inside [_MushafWordWidget]'s tap /
/// highlight box. Unlike the margin between words, this isn't reclaimed
/// when a line is tight, since shrinking it would shrink the tap target.
const double _wordPadding = 3.0;

/// The margin (each side) between words when a line has room to spare -
/// matches a comfortably spaced, real-mushaf-like word gap.
const double _maxWordMargin = 1.5;

/// The smallest that per-word margin is allowed to shrink to before falling
/// back to shrinking the font itself.
const double _minWordMargin = 0.0;

/// The rendered diameter of an [_AyahEndMarker] badge at a given line
/// [fontSize]. Kept as a shared function so the fitting calculation below
/// measures markers using their *actual* rendered width instead of the raw
/// digit glyph width (the badge is a fixed-size circle, not plain text).
double _ayahMarkerDiameter(double fontSize) =>
    (fontSize * 0.95).clamp(16.0, 24.0);

/// Renders one mushaf page: Page -> Line -> Ayah -> Word.
///
/// Fills the available width edge-to-edge (no card, border or max-width),
/// so the page reads like a real Mushaf sheet rather than a bordered card.
///
/// Every line renders at exactly [fontSize] - the same size on every page -
/// so the reading experience doesn't visibly change size as you swipe
/// between pages. Ayah lines use a right-to-left [Row] with
/// [MainAxisAlignment.spaceBetween] so words are pushed evenly across the
/// line width, replicating the physical mushaf's justified layout (the
/// Flutter equivalent of `display: flex; justify-content: space-between`
/// on `.line` in the reference HTML). Since the words render with a regular
/// Uthmani font rather than a per-line-calibrated glyph font, an unusually
/// dense line can occasionally be wider than the screen at [fontSize];
/// [_MushafLineWidget] only shrinks that one specific line just enough to
/// fit, rather than shrinking the whole page, so this stays a rare,
/// localized exception instead of making entire pages inconsistently
/// smaller than others.
///
/// When a page has fewer than [MushafPageIndex.linesPerPage] lines (e.g. the
/// very first page with Al-Fatihah, or the last page of the Quran), the
/// content can't naturally stretch edge-to-edge, so it's centered as a
/// block within the page instead of being pinned to the top.
class MushafPageWidget extends StatelessWidget {
  final MushafPage page;
  final double fontSize;
  final String fontFamily;
  final String? selectedVerseKey;
  final bool hideAyahs;
  final bool correctionMode;
  final Set<int> revealedWordIds;
  final Map<int, MushafWordLiveState> wordStates;
  final int? activeWordId;
  final Function(MushafWord) onWordTap;

  const MushafPageWidget({
    super.key,
    required this.page,
    required this.fontSize,
    required this.fontFamily,
    this.selectedVerseKey,
    this.hideAyahs = false,
    this.correctionMode = true,
    this.revealedWordIds = const {},
    this.wordStates = const {},
    this.activeWordId,
    required this.onWordTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDarkMode ? const Color(0xFFF1F1F1) : QuranyTheme.darkGreen;
    final isFullPage = page.lines.length >= MushafPageIndex.linesPerPage;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Column(
        key: const ValueKey('mushafPageColumn'),
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: isFullPage
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.center,
        children: [
          for (final line in page.lines)
            _MushafLineWidget(
              line: line,
              fontSize: fontSize,
              fontFamily: fontFamily,
              textColor: textColor,
              hideAyahs: hideAyahs,
              correctionMode: correctionMode,
              revealedWordIds: revealedWordIds,
              wordStates: wordStates,
              selectedVerseKey: selectedVerseKey,
              activeWordId: activeWordId,
              onWordTap: onWordTap,
            ),
          SizedBox(height: isFullPage ? 8 : 20),
          Text(
            '${page.pageNumber}',
            style: TextStyle(
              fontSize: 12,
              color: textColor.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// The result of fitting a line's words into the available width: either
/// the words fit at [fontSize] by adjusting [wordMargin] (the common case,
/// keeping every line's glyphs the exact same size), or - only for
/// unusually dense lines - [fontSize] itself had to shrink a little.
class _LineFit {
  final double fontSize;
  final double wordMargin;
  const _LineFit(this.fontSize, this.wordMargin);
}

/// Absolute lower bound on a shrunk line's font size. There's intentionally
/// no *relative* floor (e.g. "never below 80% of the requested size"):
/// since the margin-shrinking step above already absorbs the vast majority
/// of real mushaf lines at the full requested size, this fallback is only
/// ever reached by rare, exceptionally dense outliers, and it must
/// guarantee a fit rather than risk an overflow.
const double _minRenderedFontSize = 1.0;

/// Fits [words] into [maxWidth] at [baseFontSize].
///
/// Mirrors how a real, physically-typeset mushaf justifies a line: first
/// try tightening the gap between words (from [_maxWordMargin] down to
/// [_minWordMargin]) while keeping every glyph at exactly [baseFontSize].
/// This alone is enough for the vast majority of real mushaf lines, which
/// is what keeps the font looking the same size across the whole page.
/// Only the rare, unusually dense line (many long words on a narrow
/// screen) needs its font shrunk too, and even then only just enough to
/// fit - never further than necessary.
double _glyphWidth({
  required String text,
  required String fontFamily,
  required double fontSize,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: fontFamily, fontSize: fontSize),
    ),
    textDirection: TextDirection.rtl,
    maxLines: 1,
  )..layout();
  return painter.width;
}

_LineFit _fitLine({
  required List<MushafWord> words,
  required String fontFamily,
  required double baseFontSize,
  required double maxWidth,
  Map<int, MushafWordLiveState> wordStates = const {},
}) {
  if (maxWidth <= 0 || words.isEmpty) {
    return _LineFit(baseFontSize, _maxWordMargin);
  }

  double glyphWidthAt(double fontSize) {
    var total = 0.0;
    for (final word in words) {
      if (word.isAyahMarker) {
        total += _ayahMarkerDiameter(fontSize);
        continue;
      }
      var width = _glyphWidth(
        text: word.text,
        fontFamily: fontFamily,
        fontSize: fontSize,
      );
      final recited = wordStates[word.id]?.recitedAs;
      if (recited != null && recited.isNotEmpty) {
        final recitedWidth = _glyphWidth(
          text: recited,
          fontFamily: fontFamily,
          fontSize: fontSize * 0.65,
        );
        if (recitedWidth > width) width = recitedWidth;
      }
      total += width;
    }
    return total;
  }

  final n = words.length;
  // Conservative width budget: font metrics differ slightly across platforms
  // (Linux CI vs local), so leave extra headroom to avoid RenderFlex overflow.
  final usableWidth = maxWidth * 0.92;
  final fixedChrome = n * _wordPadding * 2;
  final availableForGlyphs = usableWidth - fixedChrome;

  final glyphWidthAtBase = glyphWidthAt(baseFontSize);
  if (glyphWidthAtBase <= 0) return _LineFit(baseFontSize, _maxWordMargin);

  final marginNeeded = (availableForGlyphs - glyphWidthAtBase) / (n * 2);
  _LineFit fit;
  if (marginNeeded >= _minWordMargin) {
    fit = _LineFit(
      baseFontSize,
      marginNeeded.clamp(_minWordMargin, _maxWordMargin),
    );
  } else {
    // Even with no gap between words the glyphs alone don't fit at
    // baseFontSize: shrink the font just enough to make them fit exactly,
    // scaling glyph width roughly linearly with font size.
    final scale = availableForGlyphs / glyphWidthAtBase;
    fit = _LineFit(
      (baseFontSize * scale).clamp(_minRenderedFontSize, baseFontSize),
      _minWordMargin,
    );
  }

  return _tightenFitUntilMeasuredWidthFits(
    words: words,
    fontFamily: fontFamily,
    fit: fit,
    maxWidth: maxWidth,
    wordStates: wordStates,
  );
}

double _measuredLineWidth({
  required List<MushafWord> words,
  required String fontFamily,
  required double fontSize,
  required double wordMargin,
  Map<int, MushafWordLiveState> wordStates = const {},
}) {
  var total = 0.0;
  for (final word in words) {
    final chrome = wordMargin * 2 + _wordPadding * 2;
    if (word.isAyahMarker) {
      total += _ayahMarkerDiameter(fontSize) + chrome;
      continue;
    }
    var width = _glyphWidth(
      text: word.text,
      fontFamily: fontFamily,
      fontSize: fontSize,
    );
    final recited = wordStates[word.id]?.recitedAs;
    if (recited != null && recited.isNotEmpty) {
      final recitedWidth = _glyphWidth(
        text: recited,
        fontFamily: fontFamily,
        fontSize: fontSize * 0.65,
      );
      if (recitedWidth > width) width = recitedWidth;
    }
    total += width + chrome;
  }
  return total;
}

/// Nudges [fit] down until the summed child widths fit [maxWidth].
_LineFit _tightenFitUntilMeasuredWidthFits({
  required List<MushafWord> words,
  required String fontFamily,
  required _LineFit fit,
  required double maxWidth,
  Map<int, MushafWordLiveState> wordStates = const {},
}) {
  var current = fit;
  for (var i = 0; i < 12; i++) {
    final measured = _measuredLineWidth(
      words: words,
      fontFamily: fontFamily,
      fontSize: current.fontSize,
      wordMargin: current.wordMargin,
      wordStates: wordStates,
    );
    if (measured <= maxWidth - 1) return current;

    final scale = (maxWidth / measured) * 0.96;
    current = _LineFit(
      (current.fontSize * scale).clamp(_minRenderedFontSize, current.fontSize),
      current.wordMargin,
    );
  }
  return current;
}

class _MushafLineWidget extends StatelessWidget {
  final MushafLine line;
  final double fontSize;
  final String fontFamily;
  final Color textColor;
  final bool hideAyahs;
  final bool correctionMode;
  final Set<int> revealedWordIds;
  final Map<int, MushafWordLiveState> wordStates;
  final String? selectedVerseKey;
  final int? activeWordId;
  final Function(MushafWord) onWordTap;

  const _MushafLineWidget({
    required this.line,
    required this.fontSize,
    required this.fontFamily,
    required this.textColor,
    this.hideAyahs = false,
    this.correctionMode = true,
    required this.revealedWordIds,
    this.wordStates = const {},
    this.selectedVerseKey,
    this.activeWordId,
    required this.onWordTap,
  });

  @override
  Widget build(BuildContext context) {
    if (line.isSurahName) {
      final surahNumber = line.surahNumber;
      final name = (surahNumber != null &&
              surahNumber >= 1 &&
              surahNumber <= AppConstants.surahNames.length)
          ? AppConstants.surahNames[surahNumber - 1]
          : '';

      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            'سورة $name',
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: fontSize * 0.9,
              fontWeight: FontWeight.bold,
              color: QuranyTheme.primary,
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    }

    if (line.isBasmallah) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Text(
            _basmallahText,
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: fontSize * 0.85,
              color: textColor,
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    }

    if (line.ayahGroups.isEmpty) {
      return const SizedBox.shrink();
    }

    final words = line.words;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fit = _fitLine(
            words: words,
            fontFamily: fontFamily,
            baseFontSize: fontSize,
            maxWidth: constraints.maxWidth,
            wordStates: wordStates,
          );

          return Flex(
            direction: Axis.horizontal,
            textDirection: TextDirection.rtl,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            clipBehavior: Clip.hardEdge,
            children: [
              for (final word in words)
                _MushafWordWidget(
                  word: word,
                  fontSize: fit.fontSize,
                  horizontalMargin: fit.wordMargin,
                  fontFamily: fontFamily,
                  textColor: textColor,
                  hideAyahs: hideAyahs,
                  correctionMode: correctionMode,
                  liveState: wordStates[word.id],
                  legacyRevealed: revealedWordIds.contains(word.id),
                  selectedVerseKey: selectedVerseKey,
                  activeWordId: activeWordId,
                  onWordTap: onWordTap,
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A single tappable word or ayah-end marker (`.char`).
class _MushafWordWidget extends StatelessWidget {
  final MushafWord word;
  final double fontSize;
  final double horizontalMargin;
  final String fontFamily;
  final Color textColor;
  final bool hideAyahs;
  final bool correctionMode;
  final MushafWordLiveState? liveState;
  final bool legacyRevealed;
  final String? selectedVerseKey;
  final int? activeWordId;
  final Function(MushafWord) onWordTap;

  const _MushafWordWidget({
    required this.word,
    required this.fontSize,
    required this.horizontalMargin,
    required this.fontFamily,
    required this.textColor,
    this.hideAyahs = false,
    this.correctionMode = true,
    this.liveState,
    this.legacyRevealed = false,
    this.selectedVerseKey,
    this.activeWordId,
    required this.onWordTap,
  });

  Color? get _backgroundColor {
    final status = liveState?.status;
    if (status == MushafWordLiveStatus.correct) {
      return QuranyTheme.correctGreen.withValues(alpha: 0.22);
    }
    if (status == MushafWordLiveStatus.wrong) {
      return QuranyTheme.errorRed.withValues(alpha: 0.22);
    }
    if (status == MushafWordLiveStatus.omitted) {
      return Colors.deepOrange.withValues(alpha: 0.22);
    }
    if (word.id == activeWordId && correctionMode) {
      return QuranyTheme.primaryGold.withValues(alpha: 0.3);
    }
    return null;
  }

  Color _resolvedTextColor(bool isSelected) {
    if (liveState != null) {
      final status = liveState!.status;
      // Free mode: hide only words not yet reached; show wrong/omitted/correct.
      if (!correctionMode && hideAyahs) {
        if (status == MushafWordLiveStatus.pending) {
          return Colors.transparent;
        }
      }
      switch (status) {
        case MushafWordLiveStatus.correct:
          return QuranyTheme.correctGreen;
        case MushafWordLiveStatus.wrong:
          return QuranyTheme.errorRed;
        case MushafWordLiveStatus.omitted:
          return Colors.deepOrange.shade800;
        case MushafWordLiveStatus.pending:
          break;
      }
    } else if (hideAyahs && !legacyRevealed) {
      return Colors.transparent;
    }
    if (isSelected) return textColor;
    return textColor;
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = word.verseKey == selectedVerseKey;
    final isActive = word.id == activeWordId;
    final bg = _backgroundColor ??
        (isActive && liveState == null
            ? QuranyTheme.primaryGold.withValues(alpha: 0.3)
            : (isSelected ? QuranyTheme.accent.withValues(alpha: 0.25) : null));
    final displayColor = _resolvedTextColor(isSelected);

    if (word.isAyahMarker) {
      return GestureDetector(
        onTap: () => onWordTap(word),
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
          child: _AyahEndMarker(
            number: word.text,
            fontSize: fontSize,
            isHighlighted: isSelected || isActive,
          ),
        ),
      );
    }

    final showRecited = liveState?.status == MushafWordLiveStatus.wrong &&
        liveState?.recitedAs != null &&
        liveState!.recitedAs!.isNotEmpty;
    final wordGlyphWidth = word.isAyahMarker
        ? _ayahMarkerDiameter(fontSize)
        : _glyphWidth(
            text: word.text,
            fontFamily: fontFamily,
            fontSize: fontSize,
          );

    return GestureDetector(
      onTap: () => onWordTap(word),
      child: RepaintBoundary(
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: _wordPadding,
            vertical: 1,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                word.text,
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: fontSize,
                  color: displayColor,
                ),
                textDirection: TextDirection.rtl,
              ),
              if (showRecited)
                SizedBox(
                  width: wordGlyphWidth,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      liveState!.recitedAs!,
                      style: TextStyle(
                        fontFamily: fontFamily,
                        fontSize: fontSize * 0.65,
                        color: QuranyTheme.errorRed.withValues(alpha: 0.85),
                      ),
                      textDirection: TextDirection.rtl,
                      maxLines: 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small decorative circle marking the end of an ayah, with its verse
/// number (in Eastern Arabic numerals, exactly as supplied by the API)
/// drawn clearly in the centre - styled like a printed mushaf ornament
/// rather than a generic star icon.
class _AyahEndMarker extends StatelessWidget {
  final String number;
  final double fontSize;
  final bool isHighlighted;

  const _AyahEndMarker({
    required this.number,
    required this.fontSize,
    required this.isHighlighted,
  });

  @override
  Widget build(BuildContext context) {
    // Keep the badge legible even when the surrounding line's font has been
    // scaled down for density - a circle that shrinks in lock-step with a
    // 9-word dense line would become illegibly small.
    final diameter = _ayahMarkerDiameter(fontSize);
    final numberSize = diameter * 0.42;
    final color = QuranyTheme.primary
        .withValues(alpha: isHighlighted ? 1 : 0.65);

    return SizedBox(
      width: diameter,
      height: diameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(diameter, diameter),
            painter: _MushafAyahCirclePainter(color: color),
          ),
          Text(
            number,
            style: TextStyle(
              fontSize: numberSize,
              fontWeight: FontWeight.w600,
              color: color,
              height: 1,
            ),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }
}

/// Double-ring circle ornament mimicking the ayah-end marker on a printed
/// mushaf page (۝), without relying on a font glyph that may not exist in
/// the selected Quran script face.
class _MushafAyahCirclePainter extends CustomPainter {
  final Color color;

  const _MushafAyahCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width * 0.44;
    final stroke = (size.width * 0.055).clamp(1.0, 2.0);

    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    canvas.drawCircle(center, outerRadius, ring);
    canvas.drawCircle(
      center,
      outerRadius * 0.72,
      ring..strokeWidth = stroke * 0.75,
    );
  }

  @override
  bool shouldRepaint(covariant _MushafAyahCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}
