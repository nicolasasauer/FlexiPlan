import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/storage_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FlexiPlanApp());
}

class FlexiPlanApp extends StatelessWidget {
  const FlexiPlanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlexiPlan',
      debugShowCheckedModeBanner: false,
      theme: _buildDarkTheme(),
      home: HomeScreen(storage: StorageService()),
    );
  }

  /// Minimalistisches Dark-Mode-Theme (Material 3): hoher Kontrast,
  /// große Schriften, großflächige Touch-Zonen.
  ThemeData _buildDarkTheme() {
    const background = Color(0xFF0E0E10);
    const surface = Color(0xFF1A1A1E);
    const accent = Color(0xFF35E07F);

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
    );

    // ThemeData.textTheme trägt zu diesem Zeitpunkt noch keine konkreten
    // fontSizes (die M3-Geometrie wird erst beim Rendern über die
    // Lokalisierung gemerged); apply(fontSizeFactor) würde auf den
    // null-Größen asserten. Daher die Geometrie explizit laden, mit den
    // Dark-Mode-Farben mergen und dann skalieren.
    final typography = Typography.material2021(platform: TargetPlatform.android);
    final scaledTextTheme = typography.englishLike
        .merge(typography.white)
        .apply(fontSizeFactor: 1.15);

    return base.copyWith(
      textTheme: scaledTextTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          textStyle: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          textStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        titleTextStyle: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 18,
          color: Colors.white70,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }
}
