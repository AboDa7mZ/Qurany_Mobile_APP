import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../services/khatmah_service.dart';
import '../../widgets/app_icons.dart';

class CreateKhatmahScreen extends StatefulWidget {
  const CreateKhatmahScreen({super.key});

  @override
  State<CreateKhatmahScreen> createState() => _CreateKhatmahScreenState();
}

class _CreateKhatmahScreenState extends State<CreateKhatmahScreen> {
  int _targetDays = 30;

  @override
  Widget build(BuildContext context) {
    int pagesPerDay = (604 / _targetDays).ceil();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('ختمة جديدة'),
        leading: AppIcons.backButton(context: context),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.menu_book_rounded,
              size: 80,
              color: QuranyTheme.primaryGreen,
            ),
            const SizedBox(height: 24),
            const Text(
              'الهدف اليومي لختم القرآن',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),

            Text('المدة: $_targetDays يوم', style: const TextStyle(fontSize: 16)),
            Slider(
              value: _targetDays.toDouble(),
              min: 5,
              max: 365,
              divisions: 360,
              activeColor: QuranyTheme.primaryGreen,
              onChanged: (val) => setState(() => _targetDays = val.toInt()),
            ),
            
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: QuranyTheme.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الورد اليومي المطلوب: ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('$pagesPerDay صفحة', style: const TextStyle(fontSize: 18, color: QuranyTheme.primaryGreen, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            const SizedBox(height: 48),

            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _createKhatmah,
                style: ElevatedButton.styleFrom(
                  backgroundColor: QuranyTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'بدء الختمة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _createKhatmah() async {
    await context.read<KhatmahService>().createKhatmah(targetDays: _targetDays);
    if (!mounted) return;
    
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم البدء بختمة القراءة بنجاح!')),
    );
  }
}
