import 'package:flutter/material.dart';
import '../screens/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/quran_reader/surah_list_screen.dart';
import '../screens/quran_reader/quran_reader_screen.dart';
import '../screens/mushaf_reader/mushaf_reader_screen.dart';
import '../screens/recitation/recitation_screen.dart';
import '../screens/recitation/recitation_result_screen.dart';
import '../screens/schedule/schedule_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/bookmarks/bookmarks_screen.dart';
import '../screens/history/history_screen.dart';
import '../screens/progress/progress_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/learning_plan/create_plan_screen.dart';
import '../screens/learning_plan/track_plan_screen.dart';
import '../screens/khatmah/create_khatmah_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/recitation/statistics_screen.dart';
import '../screens/learning_plan/plan_stats_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String surahList = '/surah-list';
  static const String quranReader = '/quran-reader';
  static const String mushafReader = '/mushaf-reader';
  static const String recitation = '/recitation';
  static const String recitationResult = '/recitation-result';
  static const String schedule = '/schedule';
  static const String search = '/search';
  static const String bookmarks = '/bookmarks';
  static const String history = '/history';
  static const String progress = '/progress';
  static const String settings = '/settings';
  static const String createPlan = '/create-plan';
  static const String trackPlan = '/track-plan';
  static const String createKhatmah = '/create-khatmah';
  static const String notifications = '/notifications';
  static const String statistics = '/statistics';
  static const String planStats = '/plan-stats';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return _fadeRoute(const SplashScreen(), settings);
      case login:
        return _slideRoute(const LoginScreen(), settings);
      case register:
        return _slideRoute(const RegisterScreen(), settings);
      case home:
        return _fadeRoute(const HomeScreen(), settings);
      case surahList:
        return _slideRoute(const SurahListScreen(), settings);
      case quranReader:
        final args = settings.arguments as Map<String, dynamic>?;
        return _slideRoute(
          QuranReaderScreen(
            surahNumber: args?['surahNumber'] ?? 1,
            surahName: args?['surahName'] ?? 'الفاتحة',
            qiraat: args?['qiraat'] ?? 'حفص',
          ),
          settings,
        );
      case mushafReader:
        final args = settings.arguments as Map<String, dynamic>?;
        return _slideRoute(
          MushafReaderScreen(
            initialPage: args?['initialPage'] as int?,
            surahNumber: args?['surahNumber'] as int?,
            initialVerseKey: args?['initialVerseKey'] as String?,
          ),
          settings,
        );
      case recitation:
        final args = settings.arguments as Map<String, dynamic>?;
        return _slideRoute(
          RecitationScreen(
            surahNumber: args?['surahNumber'],
            surahName: args?['surahName'],
            mode: args?['mode'] ?? 'free',
            qiraat: args?['qiraat'],
            planDayNumber: args?['planDayNumber'],
            planId: args?['planId'],
            startAyah: args?['startAyah'],
            endAyah: args?['endAyah'],
          ),
          settings,
        );
      case recitationResult:
        final args = settings.arguments as Map<String, dynamic>;
        return _slideRoute(
          RecitationResultScreen(resultData: args),
          settings,
        );
      case schedule:
        return _slideRoute(const ScheduleScreen(), settings);
      case search:
        return _slideRoute(const SearchScreen(), settings);
      case bookmarks:
        return _slideRoute(const BookmarksScreen(), settings);
      case history:
        return _slideRoute(const HistoryScreen(), settings);
      case progress:
        return _slideRoute(const ProgressScreen(), settings);
      case AppRoutes.settings:
        return _slideRoute(const SettingsScreen(), settings);
      case AppRoutes.createPlan:
        return _slideRoute(const CreatePlanScreen(), settings);
      case AppRoutes.trackPlan:
        final args = settings.arguments as Map<String, dynamic>?;
        return _slideRoute(
          TrackPlanScreen(
            planId: args?['planId'] as String?,
          ),
          settings,
        );
      case AppRoutes.createKhatmah:
        return _slideRoute(const CreateKhatmahScreen(), settings);
      case notifications:
        return _slideRoute(const NotificationsScreen(), settings);
      case statistics:
        final args = settings.arguments as Map<String, dynamic>?;
        return _slideRoute(
          StatisticsScreen(
            totalVerses: args?['totalVerses'] ?? 0,
            totalCorrectedFaults: args?['totalCorrectedFaults'] ?? 0,
            faultsDetail: args?['faultsDetail'] ?? <String, int>{},
            tashkeelFutures: args?['tashkeelFutures']
                    as List<Future<Map<String, dynamic>?>>? ??
                const [],
            tashkeelAyahLabels:
                args?['tashkeelAyahLabels'] as List<Map<String, dynamic>>? ??
                    const [],
          ),
          settings,
        );
      case planStats:
        final args = settings.arguments as Map<String, dynamic>?;
        return _slideRoute(
          PlanStatsScreen(
            planId: args?['planId'] as String?,
          ),
          settings,
        );
      default:
        return _fadeRoute(const HomeScreen(), settings);
    }
  }

  static PageRouteBuilder _fadeRoute(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  static PageRouteBuilder _slideRoute(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1.0, 0.0), // RTL: slide from left
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          )),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}
