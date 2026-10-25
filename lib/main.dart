import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const ProviderScope(child: MagpieApp()));
}

class MagpieApp extends StatelessWidget {
  const MagpieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Magpie',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // On web/desktop, keep a phone-sized canvas so the layout matches the
      // mobile reference.
      builder: (context, child) {
        final width = MediaQuery.sizeOf(context).width;
        if (width <= 520) return child!;
        return ColoredBox(
          color: const Color(0xFFD9D8DD),
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: SizedBox(
                width: 430,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: Size(430, MediaQuery.sizeOf(context).height),
                  ),
                  child: child!,
                ),
              ),
            ),
          ),
        );
      },
      home: const SplashScreen(),
    );
  }
}
