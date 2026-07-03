import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../config/constants.dart';
import '../../services/qiraat_service.dart';
import '../../widgets/app_icons.dart';

class SurahListScreen extends StatefulWidget {
  final bool embeddedInTab;

  const SurahListScreen({super.key, this.embeddedInTab = false});

  @override
  State<SurahListScreen> createState() => _SurahListScreenState();
}

class _SurahListScreenState extends State<SurahListScreen> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  // Check if this screen is used for selecting surah for recitation
  bool _selectForRecitation = false;
  String _recitationMode = 'free';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _selectForRecitation = args['selectForRecitation'] ?? false;
      _recitationMode = args['mode'] ?? 'free';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<int> get _filteredIndices {
    if (_searchQuery.isEmpty) {
      return List.generate(114, (i) => i);
    }
    return List.generate(114, (i) => i).where((i) {
      return AppConstants.surahNames[i].contains(_searchQuery) ||
          '${i + 1}'.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QuranyTheme.background,
      appBar: AppBar(
        title: Text(_selectForRecitation ? 'اختر السورة' : 'فهرس السور'),
        automaticallyImplyLeading: !widget.embeddedInTab,
        leading: widget.embeddedInTab
            ? null
            : AppIcons.backButton(context: context),
        actions: [
          if (!_selectForRecitation)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Consumer<QiraatService>(
                builder: (context, qiraatService, child) {
                  return DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: qiraatService.selectedQiraat,
                      icon: const Icon(Icons.arrow_drop_down, color: QuranyTheme.primaryGreen),
                      style: const TextStyle(color: QuranyTheme.primaryGreen, fontWeight: FontWeight.bold, fontFamily: 'MeQuran'),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          qiraatService.setQiraat(newValue);
                        }
                      },
                      items: <String>['حفص','البزي']
                          .map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'ابحث عن سورة...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Surah list
          Expanded(
            child: ListView.builder(
              itemCount: _filteredIndices.length,
              itemBuilder: (context, index) {
                final i = _filteredIndices[index];
                final surahNumber = i + 1;
                final surahName = AppConstants.surahNames[i];
                final verseCount = AppConstants.surahVerseCount[i];
                final revelationType = AppConstants.surahRevelationType[i];

                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: QuranyTheme.primaryGreen.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$surahNumber',
                          style: const TextStyle(
                            color: QuranyTheme.primaryGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      surahName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '$verseCount آية • $revelationType',
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: _selectForRecitation
                        ? const Icon(
                            Icons.mic_rounded,
                            size: 18,
                            color: QuranyTheme.primaryGreen,
                          )
                        : AppIcons.forwardChevron(
                            color: QuranyTheme.primaryGreen,
                            size: 18,
                          ),
                    onTap: () {
                      if (_selectForRecitation) {
                        Navigator.pushNamed(
                          context,
                          AppRoutes.recitation,
                          arguments: {
                            'surahNumber': surahNumber,
                            'surahName': surahName,
                            'mode': _recitationMode,
                          },
                        );
                      } else {
                        Navigator.pushNamed(
                          context,
                          AppRoutes.mushafReader,
                          arguments: {'surahNumber': surahNumber},
                        );
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
