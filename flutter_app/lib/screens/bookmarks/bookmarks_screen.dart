import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/bookmark_service.dart';
import '../../widgets/app_icons.dart';

class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bookmarks = context.watch<BookmarkService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('العلامات المرجعية'),
        leading: AppIcons.backButton(context: context),
        actions: [
          if (bookmarks.bookmarks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('حذف جميع العلامات؟'),
                    content: const Text(
                      'هل أنت متأكد من حذف جميع العلامات المرجعية؟',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('إلغاء'),
                      ),
                      TextButton(
                        onPressed: () {
                          bookmarks.clearAll();
                          Navigator.pop(ctx);
                        },
                        child: const Text(
                          'حذف الكل',
                          style: TextStyle(color: QuranyTheme.errorRed),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: bookmarks.bookmarks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bookmark_border,
                      size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'لا توجد علامات مرجعية',
                    style: TextStyle(fontSize: 18, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'اضغط مطولاً على أي آية لإضافة علامة',
                    style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: bookmarks.bookmarks.length,
              itemBuilder: (context, index) {
                final bookmark = bookmarks.bookmarks[index];
                return Dismissible(
                  key: Key(bookmark.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: QuranyTheme.errorRed,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) {
                    if (bookmark.pageNumber != null) {
                      bookmarks.removePageBookmark(bookmark.pageNumber!);
                    } else {
                      bookmarks.removeBookmark(
                        bookmark.surahNumber,
                        bookmark.verseNumber,
                      );
                    }
                  },
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: QuranyTheme.primaryGold.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.bookmark,
                          color: QuranyTheme.primaryGold,
                        ),
                      ),
                      title: Text(
                        bookmark.pageNumber != null
                            ? 'سورة ${bookmark.surahName} - صفحة ${bookmark.pageNumber}'
                            : 'سورة ${bookmark.surahName}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bookmark.pageNumber != null
                                ? 'تاريخ الحفظ: ${_formatDate(bookmark.dateTime)}'
                                : 'الآية ${bookmark.verseNumber} • ${_formatDate(bookmark.dateTime)}',
                          ),
                          if (bookmark.note != null && bookmark.note!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              bookmark.note!,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                      isThreeLine: bookmark.note != null && bookmark.note!.isNotEmpty,
                      trailing: AppIcons.forwardChevron(
                        size: 16,
                        color: QuranyTheme.primaryGreen,
                      ),
                      onTap: () {
                        if (bookmark.pageNumber != null) {
                           Navigator.pushNamed(
                             context,
                             AppRoutes.mushafReader,
                             arguments: {
                               'initialPage': bookmark.pageNumber,
                             },
                           );
                        } else {
                          Navigator.pushNamed(
                            context,
                            AppRoutes.mushafReader,
                            arguments: {
                              'surahNumber': bookmark.surahNumber,
                              'initialVerseKey':
                                  '${bookmark.surahNumber}:${bookmark.verseNumber}',
                            },
                          );
                        }
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
