import 'package:flutter/material.dart';
import 'package:uni_links/uni_links.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/auth_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:ui';
import 'screens/import_screen.dart';
import 'package:prophetie_app/widgets/blurred_dialog.dart';
import 'package:prophetie_app/widgets/styled_card.dart';
import 'package:prophetie_app/screens/phone_plus_screen.dart';
import 'package:provider/provider.dart';
import 'package:prophetie_app/providers/prophetie_provider.dart';
import 'package:prophetie_app/providers/traum_provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "lib/.env");

  await initializeDateFormatting('de_DE', null);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown, // Optional, meist reicht portraitUp
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark, // Android
      statusBarBrightness: Brightness.dark, // iOS
    ),
  );

  await Firebase.initializeApp();

  // Firestore setup for future user-specific storage
  FirebaseFirestore firestore = FirebaseFirestore.instance;

  final prefs = await SharedPreferences.getInstance();
  final alreadyLaunched = prefs.getBool('alreadyLaunched') ?? false;
  if (!alreadyLaunched) {
    await prefs.setBool('alreadyLaunched', true);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ProphetieProvider()),
        ChangeNotifierProvider(create: (context) => TraumProvider()),
      ],
      child: MyApp(),
    ),
  );
}

/// Widget to guard subscription state: shows PhonePlusScreen if no active plan
class SubscriptionGate extends StatefulWidget {
  final Widget child;
  const SubscriptionGate({super.key, required this.child});

  @override
  State<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends State<SubscriptionGate> {
  bool _hasAccess = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkSubscription();
  }

  Future<void> _checkSubscription() async {
    setState(() {
      _checking = false;
      _hasAccess = true; // Direkt Zugang gewähren ohne Kaufprüfung
    });
  }

  Future<Map<String, dynamic>?> _fetchReceiptInfo(String receiptData) async {
    const productionUrl = 'https://buy.itunes.apple.com/verifyReceipt';
    const sandboxUrl = 'https://sandbox.itunes.apple.com/verifyReceipt';
    final payload = json.encode({
      'receipt-data': receiptData,
      'password': dotenv.env['SHARED_SECRET'], // or import your shared secret constant
    });
    // First try production
    final prodRes = await http.post(
      Uri.parse(productionUrl),
      headers: {'Content-Type': 'application/json'},
      body: payload,
    );
    final prodJson = json.decode(prodRes.body) as Map<String, dynamic>;
    if (prodJson['status'] == 0) return prodJson;
    // Fallback to sandbox
    final sandboxRes = await http.post(
      Uri.parse(sandboxUrl),
      headers: {'Content-Type': 'application/json'},
      body: payload,
    );
    final sandboxJson = json.decode(sandboxRes.body) as Map<String, dynamic>;
    return sandboxJson['status'] == 0 ? sandboxJson : null;
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_hasAccess) {
      return const PhonePlusScreen();
    }
    return widget.child;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;
  StreamSubscription? _linkSub;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
    _handleInitialDeepLink();
    _linkSub = linkStream.listen((String? link) {
      if (link != null) {
        _handleDeepLink(link);
      }
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themePref = prefs.getString('themeMode') ?? 'system';
    setState(() {
      switch (themePref) {
        case 'light':
          _themeMode = ThemeMode.light;
          break;
        case 'dark':
          _themeMode = ThemeMode.dark;
          break;
        default:
          _themeMode = ThemeMode.system;
      }
    });
    // Ensure the themeNotifier reflects the loaded preference
    themeNotifier.value = _themeMode;
  }

  Future<void> _handleInitialDeepLink() async {
    final initialLink = await getInitialLink();
    if (initialLink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleDeepLink(initialLink);
      });
    }
  }

  void _handleDeepLink(String link) {
    final uri = Uri.parse(link);
    if (uri.path == '/add') {
      final type = uri.queryParameters['type'];
      final id = uri.queryParameters['id'];
      final creator = uri.queryParameters['creator'];
      Navigator.of(navigatorKey.currentContext!).push(
        MaterialPageRoute(
          builder: (_) => ImportScreen(type: type, id: id, creator: creator),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('de', 'DE')],
          routes: {'/authGate': (context) => const AuthGate()},
          theme: ThemeData(
            fontFamily: 'Poppins',
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF3F2F8),
            cardColor: Colors.white,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.grey,
              brightness: Brightness.light,
            ),
            chipTheme: ThemeData.light().chipTheme.copyWith(
              backgroundColor: Colors.white,
              disabledColor: Colors.white,
              selectedColor: Colors.black,
              checkmarkColor: Colors.white,
              elevation: 0,
              side: BorderSide.none, // entfernt den schwarzen Rand
              labelStyle: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w700,
                fontSize: 13, // Schriftpunktgröße um 1 verkleinert
              ),
              secondaryLabelStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13, // Schriftpunktgröße um 1 verkleinert
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: Colors.white,
              titleTextStyle: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
              contentTextStyle: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
            sliderTheme: SliderThemeData(
              // ... (your sliderTheme config here if any)
            ),
            progressIndicatorTheme: ProgressIndicatorThemeData(
              color: const Color(0xFFFF2D55),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF2D55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.grey[200],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              hintStyle: TextStyle(color: Colors.grey[600]),
            ),
          ),
          darkTheme: ThemeData(
            fontFamily: 'Poppins',
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: Colors.black,
            cardColor: const Color(0xFF1C1C1E),
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.grey,
              brightness: Brightness.dark,
            ),
            chipTheme: ThemeData.dark().chipTheme.copyWith(
              backgroundColor: const Color(0xFF1C1C1E),
              disabledColor: const Color(0xFF1C1C1E),
              selectedColor: Colors.white,
              checkmarkColor: Colors.black,

              side: BorderSide.none, // entfernt den schwarzen Rand
              labelStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13, // Schriftpunktgröße um 1 verkleinert
              ),
              secondaryLabelStyle: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w700,
                fontSize: 13, // Schriftpunktgröße um 1 verkleinert
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: const Color(0xFF121212),
              titleTextStyle: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              contentTextStyle: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
            sliderTheme: SliderThemeData(
              // ... (your sliderTheme config here if any)
            ),
            progressIndicatorTheme: ProgressIndicatorThemeData(
              color: const Color(0xFFFF2D55),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFF2D55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.grey[800],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              hintStyle: TextStyle(color: Colors.grey[400]),
            ),
          ),
          themeMode: currentMode,
          home: const AuthGate(),
        );
      },
    );
  }
}

