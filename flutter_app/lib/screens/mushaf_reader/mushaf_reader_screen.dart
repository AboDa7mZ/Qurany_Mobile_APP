import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import '../../config/mushaf_pages.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../models/mushaf_layout.dart';
import '../../models/recitation_session.dart';
import '../../services/mushaf_layout_service.dart';
import '../../services/mushaf_live_matcher.dart';
import '../../services/audio_service.dart';
import '../../services/recitation_api_service.dart';
import '../../services/bookmark_service.dart';
import '../../services/khatmah_service.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/tafsir_sheet.dart';
import '../../widgets/bookmark_note_dialog.dart';
import '../../widgets/mushaf_session_result_sheet.dart';
import 'widgets/mushaf_page_widget.dart';

/// Full 604-page Mushaf reader with live STT recitation (free + correction).
class MushafReaderScreen extends StatefulWidget {
  final int? initialPage;
  final int? surahNumber;
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
  final AudioService _audioService = AudioService();
  late final PageController _pageController;
  late int _currentPage;
  double _fontSize = 19.0;
  static const String _mushafFontFamily = 'MeQuran';
  String? _selectedVerseKey;

  /// false = correction (ayahs visible), true = free (hidden until read).
  bool _hideAyahs = false;
  bool get _correctionMode => !_hideAyahs;

  // Live recitation (device STT)
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  String _arabicLocaleId = 'ar';
  bool _speechIsListening = false;
  DateTime? _lastSpeechRestartAt;
  static const Duration _speechRestartCooldown = Duration(milliseconds: 800);
  bool _isRecording = false;
  bool _isAnalyzing = false;
  /// True only when [AudioService] owns the mic (never on Android during live STT).
  bool _usingHardwareMic = false;
  String _sessionTranscript = '';
  String _finalizedTranscript = '';
  String _lastPartialTranscript = '';
  final MushafIncrementalMatcher _liveMatcher = MushafIncrementalMatcher();
  final ValueNotifier<MushafLiveHighlight> _liveHighlight =
      ValueNotifier(MushafLiveHighlight.empty);
  final Map<int, Future<MushafPage>> _pageFutures = {};
  List<MushafWord> _currentPageWords = [];
  List<MushafWord> _matchingWords = [];
  Map<int, MushafWordLiveState> _wordStates = {};

  /// Ephemeral server report for this page session (not saved).
  Map<String, dynamic>? _sessionResult;
  String? _sessionError;

  @override
  void initState() {
    super.initState();
    _currentPage = _resolveInitialPage();
    _selectedVerseKey = widget.initialVerseKey;
    _pageController = PageController(initialPage: _currentPage - 1);
    _service.prefetchAround(_currentPage);
    _initMicAndSpeech();
  }

  Future<void> _initMicAndSpeech() async {
    await _audioService.requestPermission();
    try {
      _speechAvailable = await _speech.initialize(
        onError: (error) {
          debugPrint('Mushaf STT error: ${error.errorMsg}');
          _speechIsListening = false;
          if (_isRecording &&
              (error.errorMsg == 'error_no_match' ||
                  error.errorMsg == 'error_speech_timeout' ||
                  error.errorMsg == 'error_busy' ||
                  error.errorMsg == 'error_client')) {
            _restartSpeechListening();
          }
        },
        onStatus: (status) {
          debugPrint('Mushaf STT status: $status');
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
      if (_speechAvailable) {
        final locales = await _speech.locales();
        final arabicLocales = locales
            .where((l) => l.localeId.toLowerCase().startsWith('ar'))
            .toList();
        if (arabicLocales.isNotEmpty) {
          const preferred = ['ar-sa', 'ar-eg', 'ar-ae', 'ar'];
          for (final pref in preferred) {
            final match = arabicLocales.where(
              (l) => l.localeId.toLowerCase().startsWith(pref),
            );
            if (match.isNotEmpty) {
              _arabicLocaleId = match.first.localeId;
              break;
            }
          }
          if (_arabicLocaleId == 'ar' && arabicLocales.isNotEmpty) {
            _arabicLocaleId = arabicLocales.first.localeId;
          }
        }
        debugPrint('Mushaf STT ready — locale: $_arabicLocaleId');
      }
    } catch (e) {
      debugPrint('Mushaf STT init failed: $e');
      _speechAvailable = false;
    }
  }

  int _resolveInitialPage() {
    if (widget.initialPage != null) return widget.initialPage!;
    if (widget.initialVerseKey != null) {
      final surahNumber = int.tryParse(widget.initialVerseKey!.split(':').first);
      if (surahNumber != null) {
        return MushafPageIndex.firstPage(surahNumber);
      }
    }
    if (widget.surahNumber != null) {
      return MushafPageIndex.firstPage(widget.surahNumber!);
    }
    return 1;
  }

  @override
  void dispose() {
    if (_isRecording) {
      _speech.stop();
      if (_usingHardwareMic) {
        _audioService.cancelRecording();
      }
      WakelockPlus.disable();
    }
    _audioService.dispose();
    _liveHighlight.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<MushafPage> _loadPageCached(int pageNumber) {
    return _pageFutures.putIfAbsent(
      pageNumber,
      () => _service.loadPage(pageNumber),
    );
  }

  void _pushLiveHighlight({String? partialTailWord}) {
    if (partialTailWord != null && _liveMatcher.refIdx == 0) {
      final key = MushafLiveMatcher.matchKey(partialTailWord);
      final isBasmallahToken = MushafLiveMatcher.basmallahMatchKeys
          .any((b) => MushafLiveMatcher.matches(b, key));
      if (isBasmallahToken) partialTailWord = null;
    }
    final states = partialTailWord == null
        ? Map<int, MushafWordLiveState>.from(_liveMatcher.states)
        : _liveMatcher.statesWithPartialTail(partialTailWord);
    final next = MushafLiveHighlight(
      wordStates: states,
      activeWordId: _liveMatcher.activeWordId,
    );
    if (next == _liveHighlight.value) return;
    _liveHighlight.value = next;
  }

  String? _lastPartialSpokenWord() {
    final tail = _lastPartialTranscript.trim();
    if (tail.isEmpty) return null;
    final parts = tail.split(' ').where((w) => w.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.last;
  }

  void _syncCommittedWords(List<String> committed) {
    committed =
        MushafLiveMatcher.stripLeadingBasmallahWordKeys(committed);
    if (committed.isEmpty) return;

    if (_liveMatcher.processedTransCount > committed.length) {
      _liveMatcher.realignToCommitted(committed);
    } else if (committed.length <= _liveMatcher.processedTransCount) {
      return;
    } else {
      final newWords = committed.sublist(_liveMatcher.processedTransCount);
      _liveMatcher.ingestWords(newWords);
    }
    _wordStates = Map<int, MushafWordLiveState>.from(_liveMatcher.states);
    _pushLiveHighlight();
  }

  String _transcriptForMatching(String transcript) =>
      MushafLiveMatcher.stripLeadingBasmallahFromTranscript(transcript.trim());

  int _analysisStartAyah(int surah, int startAyah, int endAyah) {
    if (surah == 1 && startAyah == 1 && endAyah >= 2) return 2;
    return startAyah;
  }

  void _clearSessionResult() {
    _sessionResult = null;
    _sessionError = null;
  }

  ({int surah, int startAyah, int endAyah})? _ayahRangeForPage(MushafPage page) {
    final ayahNumbers = <int>{};
    var surah = MushafPageIndex.surahForPage(_currentPage);
    for (final line in page.lines) {
      for (final group in line.ayahGroups) {
        ayahNumbers.add(group.ayahNumber);
        surah = group.surahNumber;
      }
    }
    if (ayahNumbers.isEmpty) return null;
    final sorted = ayahNumbers.toList()..sort();
    return (surah: surah, startAyah: sorted.first, endAyah: sorted.last);
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
            _resetRecordingState(clearSession: true);
          });
          _service.prefetchAround(pageNumber);
          final khatmahService = context.read<KhatmahService>();
          if (khatmahService.hasActiveKhatmah) {
            khatmahService.updateProgress(pageNumber);
          }
        },
        itemBuilder: (context, index) {
          final pageNumber = index + 1;
          return FutureBuilder<MushafPage>(
            future: _loadPageCached(pageNumber),
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
                        onPressed: () {
                          _pageFutures.remove(pageNumber);
                          setState(() {});
                        },
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                );
              }
              final page = snapshot.data!;
              return LayoutBuilder(
                builder: (context, viewportConstraints) {
                  final pageBody = SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: viewportConstraints.maxHeight,
                      ),
                      child: pageNumber == _currentPage && _isRecording
                          ? ValueListenableBuilder<MushafLiveHighlight>(
                              valueListenable: _liveHighlight,
                              builder: (context, highlight, _) {
                                return MushafPageWidget(
                                  page: page,
                                  fontSize: _fontSize,
                                  fontFamily: _mushafFontFamily,
                                  selectedVerseKey: _selectedVerseKey,
                                  hideAyahs: _hideAyahs,
                                  correctionMode: _correctionMode,
                                  wordStates: highlight.wordStates,
                                  activeWordId: highlight.activeWordId,
                                  onWordTap: (word) => _onWordTap(page, word),
                                );
                              },
                            )
                          : MushafPageWidget(
                              page: page,
                              fontSize: _fontSize,
                              fontFamily: _mushafFontFamily,
                              selectedVerseKey: _selectedVerseKey,
                              hideAyahs: _hideAyahs,
                              correctionMode: _correctionMode,
                              wordStates: _wordStates,
                              onWordTap: (word) => _onWordTap(page, word),
                            ),
                    ),
                  );
                  return pageBody;
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
              tooltip: _hideAyahs
                  ? 'وضع حر — الكلمات تظهر مع قراءتك'
                  : 'وضع التصحيح — الآيات ظاهرة',
              onPressed: _isRecording
                  ? null
                  : () => setState(() => _hideAyahs = !_hideAyahs),
            ),
            IconButton(
              icon: _isAnalyzing
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Icon(
                      _isRecording ? Icons.mic : Icons.mic_none,
                      color: _isRecording
                          ? QuranyTheme.errorRed
                          : QuranyTheme.primaryGreen,
                      size: 28,
                    ),
              tooltip: _isRecording ? 'إيقاف التلاوة' : 'بدء التلاوة',
              onPressed: _isAnalyzing
                  ? null
                  : () async {
                      final page = await _service.loadPage(_currentPage);
                      if (_isRecording) {
                        await _stopRecording(page);
                      } else {
                        await _startRecording(page);
                      }
                    },
            ),
            if (_sessionResult != null || _sessionError != null)
              IconButton(
                icon: const Icon(Icons.analytics_outlined,
                    color: QuranyTheme.primaryGreen, size: 28),
                tooltip: 'عرض نتائج الجلسة',
                onPressed: () => MushafSessionResultSheet.show(
                  context,
                  result: _sessionResult,
                  pageNumber: _currentPage,
                  error: _sessionError,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _resetRecordingState({bool clearSession = false}) {
    if (_isRecording) {
      _speech.stop();
      if (_usingHardwareMic) {
        _audioService.cancelRecording();
        _usingHardwareMic = false;
      }
      WakelockPlus.disable();
    }
    _isRecording = false;
    _isAnalyzing = false;
    _wordStates = {};
    _currentPageWords = [];
    _matchingWords = [];
    _liveMatcher.reset(const []);
    _liveHighlight.value = MushafLiveHighlight.empty;
    _sessionTranscript = '';
    _finalizedTranscript = '';
    _lastPartialTranscript = '';
    if (clearSession) _clearSessionResult();
  }

  Future<void> _startRecording(MushafPage page) async {
    final hasMic = await _audioService.requestPermission();
    if (!hasMic) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يلزم إذن الميكروفون للتلاوة'),
            backgroundColor: QuranyTheme.errorRed,
          ),
        );
      }
      return;
    }

    if (!_speechAvailable) {
      await _initMicAndSpeech();
    }
    if (!_speechAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'التعرف على الكلام غير متاح. تأكد من إذن الميكروفون.',
            ),
          ),
        );
      }
      return;
    }

    _clearSessionResult();
    _currentPageWords = page.lines
        .expand((l) => l.words)
        .where((w) => !w.isAyahMarker)
        .toList();
    final pageHasBasmallah = page.lines.any((l) => l.isBasmallah);
    _matchingWords = MushafLiveMatcher.refWordsForMatching(
      _currentPageWords,
      pageHasDecorativeBasmallah: pageHasBasmallah,
    );

    _liveMatcher.reset(_matchingWords);

    setState(() {
      _isRecording = true;
      _wordStates = {};
      _sessionTranscript = '';
      _finalizedTranscript = '';
      _lastPartialTranscript = '';
      _usingHardwareMic = false;
    });
    _pushLiveHighlight();

    WakelockPlus.enable();

    // Android: hardware WAV + STT cannot share the mic — STT-only for live.
    // iOS: start WAV after STT is listening so live highlighting still works.
    _startSpeechListening();
    if (!Platform.isAndroid) {
      Future.delayed(const Duration(milliseconds: 900), () async {
        if (!_isRecording || !mounted) return;
        try {
          final started = await _audioService.startRecording();
          if (started && _isRecording && mounted) {
            _usingHardwareMic = true;
          }
        } catch (e) {
          debugPrint('Deferred WAV capture failed: $e');
        }
      });
    }
  }

  Future<void> _stopRecording(MushafPage page) async {
    await _speech.stop();
    _speechIsListening = false;
    WakelockPlus.disable();

    final transcript = _transcriptForMatching(_sessionTranscript);
    _syncCommittedWords(
      MushafLiveMatcher.allWordsFromTranscript(transcript),
    );
    _wordStates = Map<int, MushafWordLiveState>.from(_liveMatcher.states);

    setState(() {
      _isRecording = false;
      _isAnalyzing = true;
    });

    if (mounted) {
      MushafSessionResultSheet.show(
        context,
        result: null,
        pageNumber: _currentPage,
        loading: true,
      );
    }

    String? audioPath;
    if (_usingHardwareMic) {
      try {
        audioPath = await _audioService.stopRecording();
      } catch (_) {}
      _usingHardwareMic = false;
    }

    await _runServerAnalysis(page, audioPath: audioPath, transcript: transcript);
  }

  bool _hasLiveProgress() {
    return _liveMatcher.states.values.any(
      (s) => s.status != MushafWordLiveStatus.pending,
    );
  }

  void _presentSessionOutcome({
    Map<String, dynamic>? result,
    String? error,
    bool partial = false,
  }) {
    if (!mounted) return;
    Navigator.of(context).maybePop();
    MushafSessionResultSheet.show(
      context,
      result: result,
      pageNumber: _currentPage,
      error: error,
      partial: partial,
    );
  }

  Future<void> _runServerAnalysis(
    MushafPage page, {
    String? audioPath,
    required String transcript,
  }) async {
    if (!mounted) return;

    final range = _ayahRangeForPage(page);
    final localResult = _hasLiveProgress()
        ? MushafLiveMatcher.buildLocalSessionResult(
            refWords: _matchingWords,
            states: _wordStates,
          )
        : null;
    final isPartialPage = localResult != null &&
        (localResult['evaluated_words'] as int? ?? 0) <
            (localResult['total_words'] as int? ?? 0);

    if (range == null ||
        !AppConstants.isBackendSurahSupported(range.surah)) {
      setState(() {
        _isAnalyzing = false;
        _sessionError = null;
        _sessionResult = localResult;
      });
      if (localResult != null) {
        _presentSessionOutcome(result: localResult, partial: isPartialPage);
      } else {
        _presentSessionOutcome(
          error: 'تعذر تحديد نطاق الآيات أو السورة غير مدعومة على الخادم.',
        );
      }
      if (audioPath != null) {
        try {
          await File(audioPath).delete();
        } catch (_) {}
      }
      return;
    }

    final hasWav =
        audioPath != null && await File(audioPath).exists();
    if (!hasWav && transcript.isEmpty) {
      setState(() {
        _isAnalyzing = false;
        _sessionResult = localResult;
        _sessionError = localResult == null
            ? 'لم يُسمَع شيء. تحدث بوضوح قرب الميكروفون وحاول مرة أخرى.'
            : null;
      });
      if (localResult != null) {
        _presentSessionOutcome(result: localResult, partial: isPartialPage);
      } else {
        _presentSessionOutcome(error: _sessionError);
      }
      return;
    }

    if (!mounted) return;
    final api = context.read<RecitationApiService>();
    final startAyah = _analysisStartAyah(
      range.surah,
      range.startAyah,
      range.endAyah,
    );

    try {
      final Map<String, dynamic> result;
      if (hasWav) {
        result = await api.analyzeRecitation(
          audioFilePath: audioPath,
          surahNumber: range.surah,
          riwayah: 'hafs',
          startAyah: startAyah,
          endAyah: range.endAyah,
          skipBasmallah: true,
          timeout: const Duration(seconds: 180),
        );
      } else {
        result = await api.analyzeText(
          surahNumber: range.surah,
          transcribedText: transcript,
          riwayah: 'hafs',
          startAyah: startAyah,
          endAyah: range.endAyah,
          skipBasmallah: true,
          timeout: const Duration(seconds: 60),
        );
      }
      if (mounted) {
        final merged = localResult != null
            ? MushafLiveMatcher.mergeLiveIntoServerResult(
                server: result,
                local: localResult,
              )
            : result;
        final syncedStates = MushafLiveMatcher.wordStatesFromAnalysis(
          refWords: _matchingWords,
          result: merged,
        );
        setState(() {
          _isAnalyzing = false;
          _sessionResult = merged;
          _sessionError = null;
          _wordStates = syncedStates;
        });
        _pushLiveHighlight();
        _presentSessionOutcome(result: merged, partial: isPartialPage);
      }
    } catch (e) {
      debugPrint('Mushaf server analysis failed: $e');
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          if (localResult != null) {
            _sessionResult = localResult;
            _sessionError = null;
          } else {
            _sessionError =
                'تعذر تحليل التلاوة على الخادم. تحقق من الاتصال.';
            _sessionResult = null;
          }
        });
        if (localResult != null) {
          _presentSessionOutcome(result: localResult, partial: isPartialPage);
        } else {
          _presentSessionOutcome(error: _sessionError);
        }
      }
    } finally {
      if (audioPath != null) {
        try {
          await File(audioPath).delete();
        } catch (_) {}
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
    debugPrint('Mushaf STT listen (locale: $_arabicLocaleId)');
    try {
      if (_speech.isListening) _speech.stop();
    } catch (_) {}
    _speechIsListening = false;

    _speech.listen(
      onResult: _onSpeechResult,
      localeId: _arabicLocaleId,
      listenFor: const Duration(minutes: 10),
      pauseFor: const Duration(seconds: 15),
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
    final text = result.recognizedWords.trim();
    if (text.isEmpty) return;

    final segment =
        MushafLiveMatcher.stripLeadingBasmallahFromTranscript(text);
    if (segment.isEmpty) return;

    // Partial shrank inside already-locked text — ignore (no rewind).
    if (!result.finalResult &&
        _finalizedTranscript.isNotEmpty &&
        segment.length < _finalizedTranscript.length &&
        _finalizedTranscript.startsWith(segment)) {
      return;
    }

    if (result.finalResult) {
      _finalizedTranscript =
          MushafLiveMatcher.mergeTranscriptSegment(_finalizedTranscript, segment);
      _lastPartialTranscript = '';
      _sessionTranscript = _finalizedTranscript;
      _syncCommittedWords(
        MushafLiveMatcher.allWordsFromTranscript(
          _transcriptForMatching(_sessionTranscript),
        ),
      );
      return;
    }

    final String tail;
    if (_finalizedTranscript.isEmpty) {
      tail = segment;
    } else if (segment.startsWith(_finalizedTranscript)) {
      tail = segment.substring(_finalizedTranscript.length).trim();
    } else {
      // After a breath, STT often restarts with only the new words.
      tail = segment;
    }
    _lastPartialTranscript = tail;
    _sessionTranscript = tail.isEmpty
        ? _finalizedTranscript
        : MushafLiveMatcher.mergeTranscriptSegment(_finalizedTranscript, tail);

    _syncCommittedWords(
      MushafLiveMatcher.committedWordsFromTranscript(
        _transcriptForMatching(_sessionTranscript),
      ),
    );
    _pushLiveHighlight(partialTailWord: _lastPartialSpokenWord());
  }

  void _onWordTap(MushafPage page, MushafWord word) {
    if (_isRecording) return;
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

  void _showAddBookmarkDialog(
    BuildContext context,
    int surahNumber,
    String surahName,
    int pageNumber,
  ) async {
    final note = await showBookmarkNoteDialog(context);
    if (!context.mounted || note == null) return;

    context.read<BookmarkService>().addPageBookmark(
          Bookmark(
            surahNumber: surahNumber,
            surahName: surahName,
            verseNumber: 0,
            pageNumber: pageNumber,
            dateTime: DateTime.now(),
            note: note.isEmpty ? null : note,
          ),
        );
  }
}
