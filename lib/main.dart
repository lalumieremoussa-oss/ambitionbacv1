import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'accueil/splash_screen.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

final String supabaseUrl = dotenv.env['SUPA_BASE_URL']!;
final String supabaseAnonKey = dotenv.env['SUPA_BASE_ANON_KEY']!;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initServices();
  runApp(const MyApp());
}

Future<void> _initServices() async {
  try {
    await dotenv.load(fileName: "assets/.env");
    await initializeDateFormatting('fr', null);
    await Hive.initFlutter();
    await Hive.openBox('userStatsBox');
    await Hive.openBox('tv_cache');
    await Hive.openBox('messages_box');

    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );

    print("INIT OK");
  } catch (e) {
    print("INIT ERROR: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ambition+ Bac',
      theme: ThemeData(
        primaryColor: const Color(0xFFFF8C00),
        scaffoldBackgroundColor: const Color(0xFFFFF4F0),
        fontFamily: 'Montserrat',
      ),
      home: const SplashScreen(),
    );
  }
}
