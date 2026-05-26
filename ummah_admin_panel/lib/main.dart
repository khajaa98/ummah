// lib/main.dart
// =============================================================================
// Ummah Admin Portal — web entry point.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/verification_queue_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: UmmahAdminApp(),
    ),
  );
}

class UmmahAdminApp extends StatelessWidget {
  const UmmahAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ummah Admin Portal',
      debugShowCheckedModeBanner: false,

      // Serene Emerald/Teal Material 3 styling
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00796B), // Serene Teal
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
      ),
      home: const VerificationQueueScreen(),
    );
  }
}
