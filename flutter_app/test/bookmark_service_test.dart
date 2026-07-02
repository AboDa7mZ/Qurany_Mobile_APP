import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qurany_app/models/recitation_session.dart';
import 'package:qurany_app/services/bookmark_service.dart';

Bookmark _verseBookmark({required int surah, required int verse}) {
  return Bookmark(
    id: 'b-$surah-$verse',
    surahNumber: surah,
    surahName: 'الفاتحة',
    verseNumber: verse,
    dateTime: DateTime(2026, 7, 3),
    note: 'note',
  );
}

void main() {
  test('stores and removes verse bookmarks locally', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = BookmarkService(prefs);

    await service.addBookmark(_verseBookmark(surah: 1, verse: 1));
    expect(service.bookmarks, hasLength(1));
    expect(service.isBookmarked(1, 1), isTrue);

    await service.removeBookmark(1, 1);
    expect(service.bookmarks, isEmpty);
    expect(service.isBookmarked(1, 1), isFalse);
  });

  test('persists page bookmarks in SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = BookmarkService(prefs);

    await service.addPageBookmark(
      Bookmark(
        id: 'page-42',
        surahNumber: 2,
        surahName: 'البقرة',
        verseNumber: 1,
        pageNumber: 42,
        dateTime: DateTime(2026, 7, 3),
      ),
    );

    expect(service.isPageBookmarked(42), isTrue);

    final reloaded = BookmarkService(prefs);
    expect(reloaded.isPageBookmarked(42), isTrue);

    await reloaded.removePageBookmark(42);
    expect(reloaded.isPageBookmarked(42), isFalse);
  });

  test('clearAll removes every bookmark', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = BookmarkService(prefs);

    await service.addBookmark(_verseBookmark(surah: 1, verse: 1));
    await service.addPageBookmark(
      Bookmark(
        id: 'page-1',
        surahNumber: 1,
        surahName: 'الفاتحة',
        verseNumber: 1,
        pageNumber: 1,
        dateTime: DateTime(2026, 7, 3),
      ),
    );

    await service.clearAll();
    expect(service.bookmarks, isEmpty);
  });
}
