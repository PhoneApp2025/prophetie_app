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
import 'package:prophetie_app/widgets/styled_card.dart';
import 'package:provider/provider.dart';
import 'package:prophetie_app/providers/prophetie_provider.dart';
import 'package:prophetie_app/providers/traum_provider.dart';
import 'package:prophetie_app/providers/premium_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'widgets/main_navigation.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'services/sharing_intent_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'services/purchase_service.dart';
import 'services/insight_service.dart';
import 'services/metrics_service.dart';


final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);
final ValueNotifier<Locale?> localeNotifier = ValueNotifier<Locale?>(null);

/// ThemeExtension für eine einheitliche Handlebar (Design-Einstellungen).
@immutable
class HandlebarTheme extends ThemeExtension<HandlebarTheme> {
  final double trackWidth;
  final double barWidth;
  final double barHeight;
  final Color color;

  const HandlebarTheme({
    this.trackWidth = 120,
    this.barWidth = 44,
    this.barHeight = 3,
    this.color = const Color(0x33000000), // Schwarz 20% (0x33 alpha)
  });

  @override
  HandlebarTheme copyWith({
    double? trackWidth,
    double? barWidth,
    double? barHeight,
    Color? color,
  }) {
    return HandlebarTheme(
      trackWidth: trackWidth ?? this.trackWidth,
      barWidth: barWidth ?? this.barWidth,
      barHeight: barHeight ?? this.barHeight,
      color: color ?? this.color,
    );
  }

  @override
  HandlebarTheme lerp(ThemeExtension<HandlebarTheme>? other, double t) {
    if (other is! HandlebarTheme) return this;
    return HandlebarTheme(
      trackWidth: lerpDouble(trackWidth, other.trackWidth, t) ?? trackWidth,
      barWidth: lerpDouble(barWidth, other.barWidth, t) ?? barWidth,
      barHeight: lerpDouble(barHeight, other.barHeight, t) ?? barHeight,
      color: Color.lerp(color, other.color, t) ?? color,
    );
  }
}

/// Einheitliches Handlebar-Widget, das seine Werte aus dem Theme bezieht.
class Handlebar extends StatelessWidget {
  /// Optionales Override – wenn null, werden Theme-Werte genutzt.
  final double? trackWidth;
  final double? barWidth;
  final double? barHeight;
  final Color? color;

  const Handlebar({
    super.key,
    this.trackWidth,
    this.barWidth,
    this.barHeight,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<HandlebarTheme>() ?? const HandlebarTheme();
    final w = trackWidth ?? theme.trackWidth;
    final bw = barWidth ?? theme.barWidth;
    final bh = barHeight ?? theme.barHeight;
    final c = color ?? theme.color;

    return Center(
      child: SizedBox(
        width: w,
        height: 20,
        child: Center(
          child: Container(
            width: bw,
            height: bh,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a Flushbar snackbar at the top of the screen.
void showFlushbar(String message) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return; // Navigator noch nicht bereit
  Flushbar(
    message: message,
    flushbarPosition: FlushbarPosition.TOP,
    margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
    borderRadius: BorderRadius.circular(12),
    duration: const Duration(seconds: 3),
  )..show(ctx);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.deinpaket.audio',
    androidNotificationChannelName: 'Audio Playback',
    androidNotificationOngoing: true,
  );

  await dotenv.load(fileName: ".env");

  await initializeDateFormatting('de_DE', null);
  await initializeDateFormatting('en_US', null);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Firebase.initializeApp();

  // Configure RevenueCat SDK
  await Purchases.configure(
    PurchasesConfiguration(
      dotenv.env['REVENUECAT_API_KEY'] ?? 'appl_BmgohkROLRDaEyXUtsncvUcsCxN',
    ),
  );

  // Initialize PremiumProvider and RevenueCat listener
  final premiumProvider = PremiumProvider();
  PurchaseService().onPremiumChanged = (isPremium) {
    premiumProvider.setPremium(isPremium);
  };
  await PurchaseService().initWithListener((info) {
    final hasPremium = info.entitlements.active.containsKey('PHONĒ+');
    premiumProvider.setPremium(hasPremium);
  });

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
        ChangeNotifierProvider(create: (_) => ProphetieProvider()),
        ChangeNotifierProvider(create: (_) => TraumProvider()),
        ChangeNotifierProvider.value(value: premiumProvider),
      ],
      child: const MyApp(),
    ),
  );

  // Run client-side Insight housekeeping whenever a user is logged in
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      // Create/update today's insights and clean up expired items
      InsightsService.ensureDailyInsights(uid: user.uid);
      // Adjust retentionDays as you like (e.g., 14, 30, 90)
      InsightsService.cleanupOldInsights(uid: user.uid, retentionDays: 30);
      // Rebuild metrics (counts for traums/prophetien) on app start/login
      MetricsService.rebuildFromExisting(uid: user.uid);
    }
  });

  // Initialize SharingIntentService once after the first frame
  WidgetsBinding.instance.addPostFrameCallback((_) {
    SharingIntentService.init();
  });

  // ❌ KEIN SharingIntentService.init() mehr hier unten
}

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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _checking = false;
        _hasAccess = false;
      });
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data();
    if (data != null && data.containsKey('plan')) {
      final expiresAt = data['expiresAt'] as int?;
      if (expiresAt != null &&
          DateTime.fromMillisecondsSinceEpoch(expiresAt)
              .isAfter(DateTime.now())) {
        setState(() {
          _checking = false;
          _hasAccess = true;
        });
        return;
      }
    }

    setState(() {
      _checking = false;
      _hasAccess = false;
    });
  }

  Future<Map<String, dynamic>?> _fetchReceiptInfo(String receiptData) async {
    const productionUrl = 'https://buy.itunes.apple.com/verifyReceipt';
    const sandboxUrl = 'https://sandbox.itunes.apple.com/verifyReceipt';
    final payload = json.encode({
      'receipt-data': receiptData,
      'password': dotenv.env['SHARED_SECRET'],
    });
    final prodRes = await http.post(
      Uri.parse(productionUrl),
      headers: {'Content-Type': 'application/json'},
      body: payload,
    );
    final prodJson = json.decode(prodRes.body) as Map<String, dynamic>;
    if (prodJson['status'] == 0) return prodJson;
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
      return Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              try {
                await PurchaseService().presentPaywall(
                  offeringId: 'ofrng9db6804728',
                );
              } catch (e) {
                debugPrint('Paywall-Error: $e');
              }
            },
            child: const Text('Jetzt PHONĒ+ freischalten'),
          ),
        ),
      );
    }
    return widget.child;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.system;
  StreamSubscription? _linkSub;

  void _setSystemUIOverlayStyle(ThemeMode mode) {
    final isDark =
        mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    SharingIntentService.dispose();
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
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ImportScreen(type: type, id: id, creator: creator),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Falls iOS uns nur in den Vordergrund holt, aber der Stream kein Event liefert,
      // stellen wir sicher, dass der SharingIntentService bereit ist.
      SharingIntentService.init(); // tut nichts, wenn bereits initialisiert
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        _setSystemUIOverlayStyle(currentMode);
        return ValueListenableBuilder<Locale?>(
          valueListenable: localeNotifier,
          builder: (context, appLocale, __) {
            return MaterialApp(
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,
              locale: appLocale,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('de'), Locale('en')],
              routes: {
                '/authGate': (context) => const AuthGate(),
                '/subscriptionGate': (context) =>
                    const SubscriptionGate(child: MainNavigation()),
              },
              theme: ThemeData(
                fontFamily: 'Poppins',
                useMaterial3: true,
                brightness: Brightness.light,
                scaffoldBackgroundColor: const Color(0xFFF3F2F8),
                primaryColor: const Color(0xFFFF2D55),
                textSelectionTheme: const TextSelectionThemeData(
                  cursorColor: Color(0xFFFF2D55),
                ),
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
                  side: BorderSide.none,
                  labelStyle: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  secondaryLabelStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                dialogTheme: DialogThemeData(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  backgroundColor: Colors.white,
                  titleTextStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                  contentTextStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                progressIndicatorTheme: const ProgressIndicatorThemeData(
                  color: Color(0xFFFF2D55),
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  hintStyle: TextStyle(color: Colors.grey[600]),
                ),
                extensions: <ThemeExtension<dynamic>>[
                  const HandlebarTheme(
                    trackWidth: 120,
                    barWidth: 44,
                    barHeight: 3,
                    color: Color(0x33000000), // Schwarz 20%
                  ),
                ],
              ),
              darkTheme: ThemeData(
                fontFamily: 'Poppins',
                useMaterial3: true,
                brightness: Brightness.dark,
                scaffoldBackgroundColor: Colors.black,
                primaryColor: const Color(0xFFFF2D55),
                textSelectionTheme: const TextSelectionThemeData(
                  cursorColor: Color(0xFFFF2D55),
                ),
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
                  side: BorderSide.none,
                  labelStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  secondaryLabelStyle: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                dialogTheme: DialogThemeData(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  backgroundColor: const Color(0xFF121212),
                  titleTextStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  contentTextStyle: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
                progressIndicatorTheme: const ProgressIndicatorThemeData(
                  color: Color(0xFFFF2D55),
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  hintStyle: TextStyle(color: Colors.grey[400]),
                ),
                extensions: <ThemeExtension<dynamic>>[
                  HandlebarTheme(
                    trackWidth: 120,
                    barWidth: 44,
                    barHeight: 3,
                    color: Colors.white.withOpacity(0.25), // leicht stärker für Dark
                  ),
                ],
              ),
              themeMode: currentMode,
              home: const AuthGate(),
            );
          },
        );
      },
    );
  }
}