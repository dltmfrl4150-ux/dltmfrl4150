import 'package:flutter/material.dart';

import 'screens/social_login_screen.dart';
import 'state/routine_library.dart';
import 'theme/loopi_colors.dart';

void main() {
  runApp(const LoopiApp());
}

class LoopiApp extends StatefulWidget {
  const LoopiApp({super.key});

  @override
  State<LoopiApp> createState() => _LoopiAppState();
}

class _LoopiAppState extends State<LoopiApp> {
  final RoutineLibrary _library = RoutineLibrary();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LOOPI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: LoopiColors.purple),
        useMaterial3: true,
        scaffoldBackgroundColor: LoopiColors.canvas,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: LoopiColors.purple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: SocialLoginScreen(library: _library),
    );
  }
}
