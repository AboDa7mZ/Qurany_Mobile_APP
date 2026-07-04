import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import '../../config/routes.dart';
import '../../config/theme.dart';
import '../../models/mushaf_layout.dart';
import '../../models/recitation_session.dart';
import '../../services/bazzi_mushaf_layout_service.dart';
import '../../services/bookmark_service.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/tafsir_sheet.dart';
import '../../widgets/bookmark_note_dialog.dart';
import 'widgets/mushaf_page_widget.dart';

/// Mushaf-style reader for Al-Bazzi Surah Al-Baqara — same UX as Hafs mushaf
/// (page swipe, hide ayahs, in-page mic, bookmarks, tafsir).
class BazziMushafReaderScreen extends StatefulWidget {
  const BazziMushafReaderScreen({super.key});

  @override
  State<BazziMushafReaderScreen> createState() => _BazziMushafReaderScreenState();
}

class _BazziMushafReaderScreenState extends State<BazziMushafReaderScreen> {
  final BazziMushafLayoutService _layoutService = BazziMushafLayoutService();
  List<MushafPage> _pages = [];
  bool _isLoading = true;
  String? _error;

  late final PageController _pageController;
  int _currentPageIndex = 0;
  double _fontSize = 19.0;
  static const String _mushafFontFamily = 'MeQuran';
  String? _selectedVerseKey;
  bool _hideAyahs = false;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _speechIsListening = false;
  DateTime? _lastSpeechRestartAt;
  static const Duration _speechRestartCooldown = Duration(milliseconds: 1500);
  bool _isRecording = false;
  Set<int> _revealedWordIds = {};
  List<MushafWord> _currentPageWords = [];
  int? _activeWordId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadPages();
  }

  Future<void> _loadPages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final pages = await _layoutService.loadPages();
      if (mounted) {
        setState(() {
          _pages = pages;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '$e';
        });
      }
    }
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

  int get _currentPageNumber => _currentPageIndex + 1;

  @override
  Widget build(BuildContext context) {
    final bookmarkService = context.watch<BookmarkService>();
    final isPageBookmarked =
        bookmarkService.isPageBookmarked(_currentPageNumber);

    return Scaffold(
      backgroundColor: QuranyTheme.background,
      appBar: AppBar(
        title: const Text('سورة البقرة — البزي'),
        leading: AppIcons.backButton(context: context),
        actions: [
          IconButton(
            icon: Icon(
              isPageBookmarked ? Icons.bookmark : Icons.bookmark_border,
              color: isPageBookmarked ? QuranyTheme.primaryGreen : null,
            ),
            tooltip: isPageBookmarked ? 'إزالة العلامة' : 'حفظ العلامة',
            onPressed: () {
              if (isPageBookmarked) {
                bookmarkService.removePageBookmark(_currentPageNumber);
              } else {
                _showAddPageBookmark(context);
              }
            },
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
          IconButton(
            icon: const Icon(Icons.mic_rounded),
            tooltip: 'تلاوة السورة',
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.recitation, arguments: {
                'surahNumber': BazziMushafLayoutService.surahNumber,
                'surahName': 'البقرة',
                'mode': 'free',
                'qiraat': 'البزي',
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadPages,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPageIndex = index;
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
                  },
                  itemBuilder: (context, index) {
                    final page = _pages[index];
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
                              fontFamily: _mushafFontFamily,
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
                ),
      bottomNavigationBar: _isLoading || _error != null
          ? null
          : Container(
              color: QuranyTheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12) +
                  MediaQuery.of(context)
                      .padding
                      .copyWith(top: 0, left: 0, right: 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      _hideAyahs ? Icons.visibility_off : Icons.visibility,
                      color:
                          _hideAyahs ? QuranyTheme.primaryGreen : Colors.grey,
                      size: 28,
                    ),
                    tooltip: _hideAyahs ? 'إظهار الآيات' : 'إخفاء الآيات',
                    onPressed: () => setState(() => _hideAyahs = !_hideAyahs),
                  ),
                  IconButton(
                    icon: Icon(
                      _isRecording ? Icons.mic : Icons.mic_none,
                      color: _isRecording
                          ? QuranyTheme.errorRed
                          : QuranyTheme.primaryGreen,
                      size: 28,
                    ),
                    tooltip: 'تلاوة الصفحة',
                    onPressed: () {
                      if (_pages.isEmpty) return;
                      _toggleRecording(_pages[_currentPageIndex]);
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

    final bookmarks = context.read<BookmarkService>();
    final isBookmarked = bookmarks.isBookmarked(
      BazziMushafLayoutService.surahNumber,
      word.ayahNumber,
    );

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
                'الآية ${word.ayahNumber}',
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
                      fontFamily: _mushafFontFamily,
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
                leading: Icon(
                  isBookmarked ? Icons.bookmark_remove : Icons.bookmark_add,
                  color: QuranyTheme.primaryGold,
                ),
                title: Text(isBookmarked ? 'إزالة العلامة' : 'إضافة علامة'),
                onTap: () async {
                  if (isBookmarked) {
                    bookmarks.removeBookmark(
                      BazziMushafLayoutService.surahNumber,
                      word.ayahNumber,
                    );
                    Navigator.pop(ctx);
                    setState(() {});
                    return;
                  }
                  Navigator.pop(ctx);
                  final note = await showBookmarkNoteDialog(context);
                  if (!mounted || note == null) return;
                  await bookmarks.addBookmark(
                    Bookmark(
                      surahNumber: BazziMushafLayoutService.surahNumber,
                      surahName: 'البقرة',
                      verseNumber: word.ayahNumber,
                      dateTime: DateTime.now(),
                      note: note.isEmpty ? null : note,
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.copy, color: QuranyTheme.primaryGreen),
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
                leading:
                    const Icon(Icons.menu_book, color: QuranyTheme.primaryGreen),
                title: const Text('عرض التفسير'),
                onTap: () {
                  Navigator.pop(ctx);
                  showTafsirSheet(
                    context,
                    surahNumber: BazziMushafLayoutService.surahNumber,
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

  void _showAddPageBookmark(BuildContext context) async {
    final note = await showBookmarkNoteDialog(context);
    if (!context.mounted || note == null) return;
    context.read<BookmarkService>().addPageBookmark(
          Bookmark(
            surahNumber: BazziMushafLayoutService.surahNumber,
            surahName: 'البقرة',
            verseNumber: 0,
            pageNumber: _currentPageNumber,
            dateTime: DateTime.now(),
            note: note.isEmpty ? null : note,
          ),
        );
  }

  void _toggleRecording(MushafPage page) async {
    if (_isRecording) {
      _speech.stop();
      _speechIsListening = false;
      WakelockPlus.disable();
      setState(() => _isRecording = false);
    } else {
      if (!_speechAvailable) {
        _speechAvailable = await _speech.initialize(
          onError: (val) => debugPrint('STT Error: ${val.errorMsg}'),
          onStatus: (status) {
            if (status == 'listening') {
              _speechIsListening = true;
            } else if (status == 'notListening' || status == 'done') {
              _speechIsListening = false;
              if (status == 'notListening' && _isRecording) {
                _restartSpeechListening();
              }
            }
          },
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
        _startSpeechListening();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('التعرف على الصوت غير متاح. تأكد من إعطاء الصلاحيات.'),
          ),
        );
      }
    }
  }

  void _restartSpeechListening() {
    if (!_isRecording || !_speechAvailable) return;
    final now = DateTime.now();
    if (_lastSpeechRestartAt != null &&
        now.difference(_lastSpeechRestartAt!) < _speechRestartCooldown) {
      return;
    }
    _lastSpeechRestartAt = now;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (_isRecording && mounted && !_speechIsListening) {
        _startSpeechListening();
      }
    });
  }

  void _startSpeechListening() {
    if (!_speechAvailable || !_isRecording) return;
    try {
      if (_speech.isListening) _speech.stop();
    } catch (_) {}
    _speechIsListening = false;
    _speech.listen(
      onResult: _onSpeechResult,
      localeId: 'ar',
      listenFor: const Duration(seconds: 120),
      pauseFor: const Duration(seconds: 8),
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
      ),
    );
    _speechIsListening = true;
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted || !_isRecording) return;
    final recognizedText = result.recognizedWords;
    if (recognizedText.isEmpty) return;

    final transWords = _normalizeArabic(recognizedText)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();

    int ti = 0;
    int ri = 0;
    final newlyRevealed = <int>{};

    while (ti < transWords.length && ri < _currentPageWords.length) {
      final refWord = _normalizeArabic(_currentPageWords[ri].text);
      if (refWord == transWords[ti] || _isSimilar(refWord, transWords[ti])) {
        newlyRevealed.add(_currentPageWords[ri].id);
        ri++;
        ti++;
      } else {
        var foundAhead = false;
        for (var ahead = 1; ahead <= 2 && ti + ahead < transWords.length; ahead++) {
          if (refWord == transWords[ti + ahead] ||
              _isSimilar(refWord, transWords[ti + ahead])) {
            newlyRevealed.add(_currentPageWords[ri].id);
            ri++;
            ti += ahead + 1;
            foundAhead = true;
            break;
          }
        }
        if (!foundAhead) ti++;
      }
    }

    int? nextActiveId;
    if (ri < _currentPageWords.length) {
      nextActiveId = _currentPageWords[ri].id;
    }

    if ((newlyRevealed.isNotEmpty &&
            newlyRevealed.length > _revealedWordIds.length) ||
        nextActiveId != _activeWordId) {
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
}
