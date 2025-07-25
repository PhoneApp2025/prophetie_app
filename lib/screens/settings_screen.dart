import 'package:flutter/material.dart';
import 'package:prophetie_app/screens/login_screen.dart';
import '../screens/auth_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:prophetie_app/main.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:prophetie_app/widgets/blurred_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _displayName;
  String selectedLanguage = 'Deutsch';

  String _themeMode = 'system';

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = prefs.getString('themeMode') ?? 'system';
    });
  }

  Future<void> _saveThemeMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', value);
    switch (value) {
      case 'light':
        themeNotifier.value = ThemeMode.light;
        break;
      case 'dark':
        themeNotifier.value = ThemeMode.dark;
        break;
      default:
        themeNotifier.value = ThemeMode.system;
    }
    setState(() {
      _themeMode = value;
    });
  }

  @override
  void initState() {
    super.initState();
    _displayName =
        FirebaseAuth.instance.currentUser?.displayName ?? 'Unbekannt';
    _loadThemeMode();
  }

  Future<void> _deleteUserDataClient(String uid) async {
    final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);
    final batch = FirebaseFirestore.instance.batch();
    // Delete main user document
    batch.delete(userDoc);
    // Delete user subcollections
    for (final sub in ['labels', 'prophetien', 'traeume']) {
      final coll = userDoc.collection(sub);
      final snapshot = await coll.get();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
    }
    await batch.commit();
    // Recursive delete in storage
    Future<void> _deleteFolder(Reference ref) async {
      final result = await ref.listAll();
      for (final file in result.items) {
        await file.delete();
      }
      for (final prefix in result.prefixes) {
        await _deleteFolder(prefix);
      }
    }

    await _deleteFolder(FirebaseStorage.instance.ref('users/$uid'));
    // Auth deletion is handled elsewhere
  }

  Future<bool> _reauthenticateUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final providerId = user.providerData.first.providerId;

    try {
      if (providerId == 'password') {
        final currentPasswordController = TextEditingController();
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Bestätigung'),
            content: TextField(
              controller: currentPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Aktuelles Passwort',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Bestätigen'),
              ),
            ],
          ),
        );

        if (confirmed != true) return false;

        final credential = EmailAuthProvider.credential(
          email: user.email!,
          password: currentPasswordController.text,
        );
        await user.reauthenticateWithCredential(credential);
      } else if (providerId == 'google.com') {
        final googleUser = await GoogleSignIn().signIn();
        final googleAuth = await googleUser?.authentication;
        if (googleAuth == null) return false;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await user.reauthenticateWithCredential(credential);
      } else if (providerId == 'apple.com') {
        final appleCredential = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName,
          ],
        );
        final oAuthProvider = OAuthProvider('apple.com');
        final credential = oAuthProvider.credential(
          idToken: appleCredential.identityToken,
        );
        await user.reauthenticateWithCredential(credential);
      } else {
        return false;
      }
      return true;
    } catch (e) {
      showFlushbar('Fehler bei der Bestätigung: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final containerWidth = screenWidth - 32;
    final dividerIndent = containerWidth * 0.1;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Einstellungen',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color:
                Theme.of(context).textTheme.titleLarge?.color ?? Colors.black,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Section: App
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                'APP',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color:
                      Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withOpacity(0.45) ??
                      Colors.black45,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    title: Text(
                      'Name',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _displayName,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color ??
                                Colors.black,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: Theme.of(context).iconTheme.color,
                        ),
                      ],
                    ),
                    onTap: () async {
                      final controller = TextEditingController(
                        text: _displayName,
                      );
                      final newName = await showDialog<String>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Name ändern'),
                          content: TextField(
                            controller: controller,
                            decoration: const InputDecoration(
                              hintText: 'Neuer Name',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Abbrechen'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(
                                context,
                              ).pop(controller.text.trim()),
                              child: const Text('Speichern'),
                            ),
                          ],
                        ),
                      );
                      if (newName != null &&
                          newName.isNotEmpty &&
                          newName != _displayName) {
                        await FirebaseAuth.instance.currentUser
                            ?.updateDisplayName(newName);
                        setState(() {
                          _displayName = newName;
                        });
                      }
                    },
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    thickness: 1.5,
                    color: Theme.of(context).dividerColor.withOpacity(0.15),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    title: Text(
                      'Sprache',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selectedLanguage,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color ??
                                Colors.black,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: Theme.of(context).iconTheme.color,
                        ),
                      ],
                    ),
                    onTap: () {},
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    thickness: 1.5,
                    color: Theme.of(context).dividerColor.withOpacity(0.15),
                  ),
                  // Theme Mode Selection
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    title: Text(
                      'Thema',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                      ),
                    ),
                    trailing: DropdownButton<String>(
                      value: _themeMode,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                      ),
                      underline: const SizedBox(),
                      onChanged: (String? value) {
                        if (value != null) {
                          _saveThemeMode(value);
                        }
                      },
                      items: const [
                        DropdownMenuItem(value: 'system', child: Text('Auto')),
                        DropdownMenuItem(value: 'light', child: Text('Tag')),
                        DropdownMenuItem(value: 'dark', child: Text('Nacht')),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    thickness: 1.5,
                    color: Theme.of(context).dividerColor.withOpacity(0.15),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    title: Text(
                      'Benachrichtigungen',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: Theme.of(context).iconTheme.color,
                    ),
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Section: Account
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                'ACCOUNT',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color:
                      Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withOpacity(0.45) ??
                      Colors.black45,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    title: Text(
                      'Email',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          FirebaseAuth.instance.currentUser?.email ??
                              'Unbekannt',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color ??
                                Colors.black,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: Theme.of(context).iconTheme.color,
                        ),
                      ],
                    ),
                    onTap: () {},
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    thickness: 1.5,
                    color: Theme.of(context).dividerColor.withOpacity(0.15),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    title: Text(
                      'Passwort ändern',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: Theme.of(context).iconTheme.color,
                    ),
                    onTap: () async {
                      final currentController = TextEditingController();
                      final newController = TextEditingController();
                      final confirmController = TextEditingController();
                      final shouldChange =
                          await showDialog<bool>(
                            context: context,
                            barrierColor: Colors.black.withOpacity(0.05),
                            builder: (context) => BlurredDialog(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Passwort ändern',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: currentController,
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Aktuelles Passwort',
                                    ),
                                  ),
                                  TextField(
                                    controller: newController,
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Neues Passwort',
                                    ),
                                  ),
                                  TextField(
                                    controller: confirmController,
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Neues Passwort bestätigen',
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(false),
                                          child: const Text('Abbrechen'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(true),
                                          child: const Text('Ändern'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ) ??
                          false;

                      if (shouldChange) {
                        if (newController.text != confirmController.text) {
                          showFlushbar('Passwörter stimmen nicht überein');
                          return;
                        }
                        try {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user?.email != null) {
                            final cred = EmailAuthProvider.credential(
                              email: user!.email!,
                              password: currentController.text,
                            );
                            await user.reauthenticateWithCredential(cred);
                            await user.updatePassword(newController.text);
                            showFlushbar('Passwort erfolgreich geändert');
                          }
                        } catch (e) {
                          showFlushbar('Fehler beim Ändern: $e');
                        }
                      }
                    },
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    thickness: 1.5,
                    color: Theme.of(context).dividerColor.withOpacity(0.15),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    title: Text(
                      'Dein Plan',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FutureBuilder<String>(
                          future: _getUserPlanType(), // Holt den Plan-Typ
                          builder: (context, snapshot) {
                            final planText =
                                snapshot.connectionState ==
                                    ConnectionState.waiting
                                ? 'Lade...'
                                : snapshot.data ?? 'Kein Plan';
                            return Text(
                              planText,
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    Theme.of(
                                      context,
                                    ).textTheme.bodyLarge?.color ??
                                    Colors.black,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: Theme.of(context).iconTheme.color,
                        ),
                      ],
                    ),
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Section: More
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                'MORE',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color:
                      Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withOpacity(0.45) ??
                      Colors.black45,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    title: Text(
                      'Hilfe & Support',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: Theme.of(context).iconTheme.color,
                    ),
                    onTap: () async {
                      final Uri emailUri = Uri(
                        scheme: 'mailto',
                        path: 'phone@simonnikel.de',
                        queryParameters: {'subject': 'Hilfe und Support'},
                      );
                      if (await canLaunchUrl(emailUri)) {
                        await launchUrl(emailUri);
                      } else {
                        showFlushbar('Konnte E-Mail-App nicht öffnen');
                      }
                    },
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    thickness: 1.5,
                    color: Theme.of(context).dividerColor.withOpacity(0.15),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    title: Text(
                      'Account löschen',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: Theme.of(context).iconTheme.color,
                    ),
                    onTap: () async {
                      final shouldDelete =
                          await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Account löschen'),
                              content: const Text(
                                'Bist du sicher, dass dein Account gelöscht wird?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(false),
                                  child: const Text('Abbrechen'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(true),
                                  child: const Text('Bestätigen'),
                                ),
                              ],
                            ),
                          ) ??
                          false;
                      if (!shouldDelete) return;
                      final user = FirebaseAuth.instance.currentUser;
                      if (user == null) {
                        showFlushbar('Kein eingeloggter Nutzer gefunden');
                        return;
                      }
                      final success = await _reauthenticateUser();
                      if (!success) return;

                      try {
                        await _deleteUserDataClient(user.uid);
                        await user.delete();
                        await FirebaseAuth.instance.signOut();
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/authGate',
                          (route) => false,
                        );
                      } catch (e) {
                        showFlushbar('Fehler beim Löschen: $e');
                      }
                    },
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    thickness: 1.5,
                    color: Theme.of(context).dividerColor.withOpacity(0.15),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    title: Text(
                      'Feedback geben',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: Theme.of(context).iconTheme.color,
                    ),
                    onTap: () async {
                      final Uri emailUri = Uri(
                        scheme: 'mailto',
                        path: 'phone@simonnikel.de',
                        queryParameters: {'subject': 'Feedback'},
                      );
                      if (await canLaunchUrl(emailUri)) {
                        await launchUrl(emailUri);
                      } else {
                        showFlushbar('Konnte E-Mail-App nicht öffnen');
                      }
                    },
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    thickness: 1.5,
                    color: Theme.of(context).dividerColor.withOpacity(0.15),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    title: Text(
                      'Datenschutz',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                      ),
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: Theme.of(context).iconTheme.color,
                    ),
                    onTap: () async {
                      await launchUrlString(
                        'https://www.notion.so/Datenschutz-21c017fc7cf7802ba0a9e2b7680a8b4a?source=copy_link',
                        mode: LaunchMode.inAppWebView,
                      );
                    },
                  ),
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    thickness: 1.5,
                    color: Theme.of(context).dividerColor.withOpacity(0.15),
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 0,
                    ),
                    leading: const Icon(Icons.logout, color: Colors.redAccent),
                    title: const Text(
                      'Abmelden',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.redAccent,
                      ),
                    ),
                    onTap: () async {
                      await FirebaseAuth.instance.signOut();
                      Navigator.of(context).pushAndRemoveUntil(
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => LoginScreen(),
                          transitionsBuilder: (_, animation, __, child) =>
                              FadeTransition(opacity: animation, child: child),
                          transitionDuration: const Duration(milliseconds: 350),
                        ),
                        (route) => false,
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'Version 1.0.0',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withOpacity(0.54) ??
                      Colors.black54,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<String> _getUserPlanType() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 'Unbekannt';
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final plan = doc.data()?['plan'];
    if (plan == 'monthly') return 'Monatlich';
    if (plan == 'yearly') return 'Jährlich';
    return 'Kein Plan';
  }
}
