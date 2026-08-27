import 'package:flutter/material.dart';

import '../state/routine_library.dart';
import '../theme/loopi_colors.dart';
import '../widgets/app_logo.dart';
import 'home_dashboard_screen.dart';

class SocialLoginScreen extends StatelessWidget {
  const SocialLoginScreen({super.key, required this.library});

  final RoutineLibrary library;

  void _continueAsGuest(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => HomeDashboardScreen(library: library),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF111116);
    const panel = Color(0xFF1B1B22);
    const textPrimary = Color(0xFFF7F6FA);
    const textMuted = Color(0xFF9997A5);

    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: LoopiColors.purple,
          brightness: Brightness.dark,
        ),
      ),
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    Container(
                      color: Colors.transparent,
                      child: const AppLogo(height: 72),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '유튜브 구간 반복 학습 루틴',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 48),
                    _SocialButton(
                      label: '카카오로 시작하기',
                      backgroundColor: const Color(0xFFFEE500),
                      foregroundColor: const Color(0xFF191600),
                      icon: Icons.chat_bubble,
                      onPressed: () {},
                    ),
                    const SizedBox(height: 12),
                    _SocialButton(
                      label: '구글로 시작하기',
                      backgroundColor: panel,
                      foregroundColor: textPrimary,
                      icon: Icons.g_mobiledata,
                      outlined: true,
                      onPressed: () {},
                    ),
                    const SizedBox(height: 12),
                    _SocialButton(
                      label: '애플로 시작하기',
                      backgroundColor: panel,
                      foregroundColor: textPrimary,
                      icon: Icons.apple,
                      outlined: true,
                      onPressed: () {},
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => _continueAsGuest(context),
                        style: TextButton.styleFrom(
                          foregroundColor: textMuted,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('게스트로 둘러보기'),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '계속 진행하면 LOOPI 이용약관 및 개인정보 처리방침에 동의하게 됩니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64626D), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.onPressed,
    this.outlined = false,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final VoidCallback onPressed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 23),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          side: outlined ? const BorderSide(color: Color(0xFF35353E)) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
