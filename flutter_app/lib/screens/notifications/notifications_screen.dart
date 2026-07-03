import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../widgets/app_icons.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QuranyTheme.background,
      appBar: AppBar(
        title: const Text('الإشعارات'),
        leading: AppIcons.backButton(context: context),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 80,
              color: QuranyTheme.primaryGreen.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'لا توجد إشعارات جديدة',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
