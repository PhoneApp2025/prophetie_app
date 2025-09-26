import 'package:provider/provider.dart';
import '../providers/premium_provider.dart';
import '../data/globals.dart';
import '../services/purchase_service.dart';
import '../screens/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? pageTitle; // z.B. "Profile" oder null für Home
  final bool isHome;
  const CustomAppBar({super.key, this.pageTitle, this.isHome = false});

  String _timeOfDayGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'Morgen';
    if (hour < 17) return 'Mittag';
    return 'Abend';
  }

  String _firstNameFromDisplayName(String? displayName) {
    if (displayName == null || displayName.trim().isEmpty) return '';
    final parts = displayName.trim().split(RegExp(r"\s+"));
    return parts.first;
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = context.watch<PremiumProvider>().isPremium;
    final String dateString =
        "${DateFormat.MMMM('de_DE').format(DateTime.now())} ${DateTime.now().day}";

    return SafeArea(
      bottom: false,
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Links: App Name + Datum/Sektion
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset(
                        Theme.of(context).brightness == Brightness.dark
                            ? 'assets/images/logo_white.png'
                            : 'assets/images/logo_black.png',
                        height: 25,
                        width: 25,
                      ),
                      SizedBox(width: 6),
                      Text(
                        "PHONĒ",
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black,
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -2,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 0),
                  Text(
                    (isHome)
                        ? (() {
                            final firstName = _firstNameFromDisplayName(
                                FirebaseAuth.instance.currentUser?.displayName);
                            final greet = _timeOfDayGreeting();
                            return firstName.isNotEmpty
                                ? '$greet, $firstName!'
                                : '$greet!';
                          })()
                        : (pageTitle ?? dateString), // Datum oder Seitentitel
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -2,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            // Rechts: Conditional Button
            (isHome && !isPremium)
                ? ElevatedButton(
                    onPressed: () async {
                      try {
                        await PurchaseService().presentPaywall(
                          offeringId: 'ofrng9db6804728',
                        );
                      } catch (e) {
                        debugPrint('Paywall-Error: $e');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF2D55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      "Get PHONĒ+",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: -0.5,
                      ),
                    ),
                  )
                : IconButton(
                    icon: Icon(
                      Icons.notifications,
                      color: Theme.of(context).iconTheme.color,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  const NotificationsScreen(),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                                const begin = Offset(1.0, 0.0);
                                const end = Offset.zero;
                                const curve = Curves.ease;
                                final tween = Tween(
                                  begin: begin,
                                  end: end,
                                ).chain(CurveTween(curve: curve));
                                final offsetAnimation = animation.drive(tween);
                                return SlideTransition(
                                  position: offsetAnimation,
                                  child: child,
                                );
                              },
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(72);
}
