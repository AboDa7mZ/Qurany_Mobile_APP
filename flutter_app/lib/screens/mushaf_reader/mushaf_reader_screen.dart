import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import '../../config/mushaf_pages.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../config/routes.dart';
import '../../models/mushaf_layout.dart';
import '../../models/recitation_session.dart';
import '../../services/mushaf_layout_service.dart';
import '../../services/bookmark_service.dart';
import '../../services/khatmah_service.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/tafsir_sheet.dart';
import 'widgets/mushaf_page_widget.dart';

/// Full 604-page Mushaf reader. Pages are fetched lazily via
/// [MushafLayoutService] as the user swipes, with in-memory + on-disk
/// caching so re-visiting a page (or reopening the app) doesn't require a
/// fresh network round-trip every time.
class MushafReaderScreen extends StatefulWidget {
  /// 1-indexed mushaf page (1..604) to open on. Takes precedence over
  /// [surahNumber] when both are provided.
  final int? initialPage;

  /// If [initialPage] isn't provided, opens on this Surah's first page.
  final int? surahNumber;

  /// Optional verse key (e.g. "18:110") to highlight/scroll to on open.
  final String? initialVerseKey;

  const MushafReaderScreen({
    super.key, 
    this.initialPage, 
    this.surahNumber,
    this.initialVerseKey,
  });

  @override
  State<MushafReaderScreen> createState() => _MushafReaderScreenState();
}

class _MushafReaderScreenState extends State<MushafReaderScreen> {
  final MushafLayoutService _service = MushafLayoutService();
  late final PageController _pageController;
  late int _currentPage;
  // Slightly smaller than a "print-perfect" size so that fonts with wider
  // natural letterforms (e.g. MeQuran, Nastaleeq) have enough headroom to
  // fit real mushaf lines on narrower phones without needing to shrink.
  double _fontSize = 19.0;
  String _selectedFontFamily = 'QPCHafs';
  String? _selectedVerseKey;
  bool _hideAyahs = false;

  // In-place recitation state
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isRecording = false;
  Set<int> _revealedWordIds = {};
  List<MushafWord> _currentPageWords = [];
  int? _activeWordId;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage ??
        (widget.surahNumber != null
            ? MushafPageIndex.firstPage(widget.surahNumber!)
            : 1);
    _selectedVerseKey = widget.initialVerseKey;
    _pageController = PageController(initialPage: _currentPage - 1);
    _service.prefetchAround(_currentPage);
  }

  @override
  void dispose() {
    if (_isRecording) {
      _speech.stop();
      WakelockPlus.disable();
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int surahNumber = MushafPageIndex.surahForPage(_currentPage);
    final String surahName = AppConstants.surahNames[surahNumber - 1];
    final bookmarkService = context.watch<BookmarkService>();
    final isBookmarked = bookmarkService.isPageBookmarked(_currentPage);

    return Scaffold(
      backgroundColor: QuranyTheme.background,
      appBar: AppBar(
        title: Text('سورة $surahName'),
        leading: AppIcons.backButton(context: context),
        actions: [
          IconButton(
            icon: Icon(
              isBookmarked ? Icons.bookmark : Icons.bookmark_border,
              color: isBookmarked ? QuranyTheme.primaryGreen : null,
            ),
            tooltip: isBookmarked ? 'إزالة العلامة' : 'حفظ العلامة',
            onPressed: () {
              if (isBookmarked) {
                bookmarkService.removePageBookmark(_currentPage);
              } else {
                _showAddBookmarkDialog(context, surahNumber, surahName, _currentPage);
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.font_download_outlined),
            tooltip: 'تغيير الخط',
            onSelected: (value) => setState(() => _selectedFontFamily = value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'QPCHafs', child: Text('حفص (QPC)')),
              PopupMenuItem(
                  value: 'KFGQPCNastaleeq', child: Text('نستعليق')),
              PopupMenuItem(value: 'MeQuran', child: Text('MeQuran')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.text_decrease),
            tooltip: 'تصغير الخط',
            onPressed: () {
              if (_fontSize > 14) setState(() => _fontSize -= 2);
            },
          ),
          IconButton(
            icon: const Icon(Icons.text_increase),
            tooltip: 'تكبير الخط',
            onPressed: () {
              if (_fontSize < 34) setState(() => _fontSize += 2);
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: MushafPageIndex.totalPages,
        onPageChanged: (index) {
          final pageNumber = index + 1;
          setState(() {
            _currentPage = pageNumber;
            _selectedVerseKey = null;
            if (_isRecording) {
               _isRecording = false;
               _speech.stop();
               WakelockPlus.disable();
            }
            _revealedWordIds.clear();
            _currentPageWords.clear();
            _activeWordId = null;
          });
          _service.prefetchAround(pageNumber);
          
          // Update Khatmah progress if active
          final khatmahService = context.read<KhatmahService>();
          if (khatmahService.hasActiveKhatmah) {
            khatmahService.updateProgress(pageNumber);
          }
        },
        itemBuilder: (context, index) {
          final pageNumber = index + 1;
          return FutureBuilder<MushafPage>(
            future: _service.loadPage(pageNumber),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError || !snapshot.hasData) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: QuranyTheme.errorRed),
                      const SizedBox(height: 12),
                      const Text(
                        'تعذر تحميل الصفحة. تأكد من اتصالك بالإنترنت.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => setState(() {}),
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                );
              }

              final page = snapshot.data!;
              return LayoutBuilder(
                builder: (context, viewportConstraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: viewportConstraints.maxHeight,
                      ),
                      child: MushafPageWidget(
                        page: page,
                        fontSize: _fontSize,
                        fontFamily: _selectedFontFamily,
                        selectedVerseKey: _selectedVerseKey,
                        hideAyahs: _hideAyahs,
                        revealedWordIds: _revealedWordIds,
                        activeWordId: _activeWordId,
                        onWordTap: (word) => _onWordTap(page, word),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      bottomNavigationBar: Container(
        color: QuranyTheme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12) +
            MediaQuery.of(context).padding.copyWith(top: 0, left: 0, right: 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: Icon(
                _hideAyahs ? Icons.visibility_off : Icons.visibility,
                color: _hideAyahs ? QuranyTheme.primaryGreen : Colors.grey,
                size: 28,
              ),
              tooltip: _hideAyahs ? 'إظهار الآيات' : 'إخفاء الآيات',
              onPressed: () => setState(() => _hideAyahs = !_hideAyahs),
            ),
            IconButton(
              icon: Icon(
                _isRecording ? Icons.mic : Icons.mic_none,
                color: _isRecording ? QuranyTheme.errorRed : QuranyTheme.primaryGreen,
                size: 28,
              ),
              tooltip: 'تلاوة الصفحة',
              onPressed: () async {
                 final page = await _service.loadPage(_currentPage);
                 _toggleRecording(page);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _onWordTap(MushafPage page, MushafWord word) {
    setState(() => _selectedVerseKey = word.verseKey);

    final ayahText = page.lines
        .expand((l) => l.ayahGroups)
        .where((g) => g.verseKey == word.verseKey)
        .expand((g) => g.words)
        .where((w) => !w.isAyahMarker)
        .map((w) => w.text)
        .join(' ');

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'الآية ${word.verseKey}',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 140),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    ayahText,
                    style: const TextStyle(
                      fontFamily: 'QPCHafs',
                      fontSize: 20,
                      height: 1.8,
                    ),
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.copy, color: QuranyTheme.primaryGreen),
                title: const Text('نسخ الآية'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: ayahText));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ الآية')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.menu_book, color: QuranyTheme.primaryGreen),
                title: const Text('عرض التفسير'),
                onTap: () {
                  Navigator.pop(ctx);
                  showTafsirSheet(
                    context,
                    surahNumber: word.surahNumber,
                    ayahNumber: word.ayahNumber,
                    verseLabel: word.verseKey,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleRecording(MushafPage page) async {
    if (_isRecording) {
      _speech.stop();
      WakelockPlus.disable();
      setState(() => _isRecording = false);
    } else {
      if (!_speechAvailable) {
        _speechAvailable = await _speech.initialize(
          onError: (val) => debugPrint('STT Error: ${val.errorMsg}'),
          onStatus: (val) => debugPrint('STT Status: $val'),
        );
      }
      if (_speechAvailable) {
        setState(() {
          _isRecording = true;
          _revealedWordIds.clear();
          _activeWordId = null;
          _currentPageWords = page.lines
              .expand((l) => l.words)
              .where((w) => !w.isAyahMarker)
              .toList();
          if (_currentPageWords.isNotEmpty) {
             _activeWordId = _currentPageWords.first.id;
          }
        });
        WakelockPlus.enable();
        _speech.listen(
          onResult: _onSpeechResult,
          localeId: 'ar',
          listenFor: const Duration(seconds: 120),
          pauseFor: const Duration(seconds: 5),
          listenOptions: stt.SpeechListenOptions(
            listenMode: stt.ListenMode.dictation,
            cancelOnError: false,
            partialResults: true,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('التعرف على الصوت غير متاح. تأكد من إعطاء الصلاحيات.')),
        );
      }
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted || !_isRecording) return;
    final recognizedText = result.recognizedWords;
    if (recognizedText.isEmpty) return;

    final transWords = _normalizeArabic(recognizedText).split(' ').where((w) => w.isNotEmpty).toList();
    
    int ti = 0;
    int ri = 0;
    Set<int> newlyRevealed = {};

    while (ti < transWords.length && ri < _currentPageWords.length) {
      final refWord = _normalizeArabic(_currentPageWords[ri].text);
      if (refWord == transWords[ti] || _isSimilar(refWord, transWords[ti])) {
        newlyRevealed.add(_currentPageWords[ri].id);
        ri++;
        ti++;
      } else {
         bool foundAhead = false;
         for (int ahead = 1; ahead <= 2 && ti + ahead < transWords.length; ahead++) {
            if (refWord == transWords[ti + ahead] || _isSimilar(refWord, transWords[ti + ahead])) {
               newlyRevealed.add(_currentPageWords[ri].id);
               ri++;
               ti += ahead + 1;
               foundAhead = true;
               break;
            }
         }
         if (!foundAhead) {
            ti++;
         }
      }
    }
    
    int? nextActiveId;
    if (ri < _currentPageWords.length) {
       nextActiveId = _currentPageWords[ri].id;
    }
    
    if ((newlyRevealed.isNotEmpty && newlyRevealed.length > _revealedWordIds.length) || nextActiveId != _activeWordId) {
       setState(() {
         _revealedWordIds = newlyRevealed;
         _activeWordId = nextActiveId;
       });
    }
  }

  bool _isSimilar(String a, String b) {
    if (a == b) return true;
    final setA = a.runes.toSet();
    final setB = b.runes.toSet();
    final intersection = setA.intersection(setB);
    final union = setA.union(setB);
    if (union.isEmpty) return false;
    return intersection.length / union.length > 0.6;
  }

  String _normalizeArabic(String text) {
    text = text.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    text = text.replaceAll('\u0640', '');
    text = text.replaceAll(RegExp(r'[\u0625\u0623\u0622\u0627]'), '\u0627');
    text = text.replaceAll(RegExp(r'[^\u0621-\u064A\s]'), '');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void _showAddBookmarkDialog(BuildContext context, int surahNumber, String surahName, int pageNumber) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة علامة مرجعية', textAlign: TextAlign.right),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(
            hintText: 'أضف ملاحظة (اختياري)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final note = noteController.text.trim();
              context.read<BookmarkService>().addPageBookmark(Bookmark(
                surahNumber: surahNumber,
                surahName: surahName,
                verseNumber: 0,
                pageNumber: pageNumber,
                dateTime: DateTime.now(),
                note: note.isNotEmpty ? note : null,
              ));
              Navigator.pop(context);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

