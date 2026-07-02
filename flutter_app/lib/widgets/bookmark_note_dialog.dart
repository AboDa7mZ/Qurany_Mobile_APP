import 'package:flutter/material.dart';

/// Shows an optional-note dialog when saving a bookmark.
Future<String?> showBookmarkNoteDialog(
  BuildContext context, {
  String title = 'إضافة علامة مرجعية',
}) async {
  return showDialog<String?>(
    context: context,
    builder: (ctx) {
      final noteController = TextEditingController();

      return AlertDialog(
        title: Text(title, textAlign: TextAlign.right),
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final trimmed = noteController.text.trim();
              Navigator.pop(ctx, trimmed.isEmpty ? '' : trimmed);
            },
            child: const Text('حفظ'),
          ),
        ],
      );
    },
  );
}
