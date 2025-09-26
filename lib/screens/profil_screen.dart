import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/custom_app_bar.dart';
import 'about_screen.dart';
import 'settings_screen.dart';
import 'traeumelexikon_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:prophetie_app/screens/send_recordings_screen.dart';
import 'package:prophetie_app/screens/uebereinstimmungen_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../screens/saved_favorites_screen.dart';

class ProfilScreen extends StatefulWidget {
  const ProfilScreen({super.key});
  @override
  State<ProfilScreen> createState() => _ProfilScreenState();
}

class _ProfilScreenState extends State<ProfilScreen> {
  String? _photoUrl;
  final ImagePicker _picker = ImagePicker();

  String _searchQuery = '';
  List<Map<String, dynamic>> _searchResults = [];

  // Predefined list of available screens/features with title and navigation callback
  late final List<Map<String, dynamic>> _allScreens = [
    {
      'title': 'Einstellungen',
      'icon': Icons.settings,
      'onTap': () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
    },
    {
      'title': 'Sprache (Einstellungen)',
      'icon': Icons.language,
      'onTap': () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const SettingsScreen(initialSection: 'language'),
        ),
      ),
    },
    {
      'title': 'Träume-Lexikon',
      'icon': Icons.book,
      'onTap': () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => TraeumeLexikonScreen())),
    },
    {
      'title': 'Gesendete Aufnahmen',
      'icon': Icons.send_time_extension,
      'onTap': () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SendRecordingsScreen())),
    },
    {
      'title': 'Über die App',
      'icon': Icons.info,
      'onTap': () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
    },
    {
      'title': 'Instagram',
      'icon': Icons.camera_alt, // fallback only
      'svgAsset': 'assets/icons/instagram.svg',
      'onTap': () {
        launchUrl(
          Uri.parse(
            'https://www.instagram.com/phoneapp.de?igsh=MWVpNm8wNnV2aWZnMg==',
          ),
          mode: LaunchMode.externalApplication,
        );
      },
    },
    // Uncomment below if SavedFavoritesScreen is enabled
    // {
    //   'title': 'Gespeichert',
    //   'icon': Icons.bookmark,
    //   'onTap': () => Navigator.of(context).push(
    //         MaterialPageRoute(builder: (_) => SavedFavoritesScreen()),
    //       ),
    // },
  ];

  void _updateSearchResults(String query) {
    setState(() {
      _searchQuery = query;
      if (_searchQuery.isEmpty) {
        _searchResults = [];
      } else {
        _searchResults = _allScreens
            .where(
              (screen) => screen['title'].toString().toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ),
            )
            .toList();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _photoUrl = user?.photoURL?.replaceFirst(RegExp(r'=s\\d+-c'), '=s96-c');
  }

  Future<void> _changeProfilePicture() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null) return;
    final file = File(picked.path);
    final userId = user.uid;
    final ref = FirebaseStorage.instance.ref().child(
      'users/$userId/profile-pictures/${user.uid}.jpg',
    );
    await ref.putFile(file);
    final url = await ref.getDownloadURL();
    await user.updatePhotoURL(url);
    setState(() {
      _photoUrl = url;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Unbekannt';
    final email = user?.email ?? '';

    Widget avatar = GestureDetector(
      onTap: _changeProfilePicture,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey,
          image: _photoUrl != null
              ? DecorationImage(
                  image: NetworkImage(_photoUrl!),
                  fit: BoxFit.contain,
                )
              : null,
        ),
        child: _photoUrl == null
            ? const Icon(Icons.person, color: Colors.white, size: 48)
            : null,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: const CustomAppBar(pageTitle: "Profil"),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(top: kToolbarHeight + 80),
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                children: [
                  // Suche oben
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 40,
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Suchen',
                              prefixIcon: const Icon(Icons.search, size: 18),
                              isDense: true,
                              filled: true,
                              fillColor:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.grey[850]
                                  : Colors.grey[200],
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            style: const TextStyle(fontSize: 14),
                            readOnly: false,
                            onChanged: _updateSearchResults,
                            controller:
                                TextEditingController(text: _searchQuery)
                                  ..selection = TextSelection.fromPosition(
                                    TextPosition(offset: _searchQuery.length),
                                  ),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          Container(
                            constraints: const BoxConstraints(maxHeight: 220),
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: _searchResults.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      "Keine Ergebnisse",
                                      style: TextStyle(
                                        fontSize: 14,
                                        color:
                                            Theme.of(
                                              context,
                                            ).textTheme.bodyLarge?.color ??
                                            Colors.black,
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: _searchResults.length,
                                    itemBuilder: (context, index) {
                                      final result = _searchResults[index];
                                      return ListTile(
                                        dense: true,
                                        leading: (result['svgAsset'] != null)
                                            ? SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: SvgPicture.asset(
                                                  result['svgAsset'],
                                                  width: 20,
                                                  height: 20,
                                                  fit: BoxFit.contain,
                                                ),
                                              )
                                            : Icon(
                                                result['icon'],
                                                color: Theme.of(
                                                  context,
                                                ).iconTheme.color,
                                              ),
                                        title: Text(
                                          result['title'],
                                          style: TextStyle(
                                            fontSize: 14,
                                            color:
                                                Theme.of(
                                                  context,
                                                ).textTheme.bodyLarge?.color ??
                                                Colors.black,
                                          ),
                                        ),
                                        onTap: () {
                                          // Clear search and close keyboard before navigating
                                          FocusScope.of(context).unfocus();
                                          setState(() {
                                            _searchQuery = '';
                                            _searchResults = [];
                                          });
                                          result['onTap']();
                                        },
                                      );
                                    },
                                  ),
                          ),
                      ],
                    ),
                  ),

                  // Profilkarte im iOS-Stil
                  Card(
                    elevation: 0,
                    color: Theme.of(context).cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Avatar links (antippbar zum Ändern)
                              GestureDetector(
                                onTap: _changeProfilePicture,
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.grey,
                                    image: _photoUrl != null
                                        ? DecorationImage(
                                            image: NetworkImage(_photoUrl!),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: _photoUrl == null
                                      ? const Icon(
                                          Icons.person,
                                          color: Colors.white,
                                          size: 36,
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 14),
                              // Name groß
                              Expanded(
                                child: Text(
                                  displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.color ??
                                        Colors.black,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // QR-Code Button entfernt (bewusst deaktiviert)
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        // Avatar-Eintrag
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          leading: Icon(
                            Icons.emoji_emotions_outlined,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          title: Text(
                            'Avatar',
                            style: TextStyle(
                              fontSize: 14,
                              color:
                                  Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color ??
                                  Colors.black,
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          onTap: _changeProfilePicture,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  // Erste Karte: Einstellungen, Träume-Lexikon, Gesendete Aufnahmen, Gespeichert
                  Card(
                    elevation: 0,
                    color: Theme.of(context).cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          leading: Icon(
                            Icons.settings,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          title: Text(
                            "Einstellungen",
                            style: TextStyle(
                              fontSize: 14,
                              color:
                                  Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color ??
                                  Colors.black,
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          ),
                        ),
                        const Divider(height: 1, indent: 17, endIndent: 16),
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          leading: Icon(
                            Icons.book,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          title: Text(
                            "Träume-Lexikon",
                            style: TextStyle(
                              fontSize: 14,
                              color:
                                  Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color ??
                                  Colors.black,
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TraeumeLexikonScreen(),
                            ),
                          ),
                        ),
                        // const Divider(height: 1, indent: 17, endIndent: 16),
                        // ListTile(
                        //   dense: true,
                        //   contentPadding: const EdgeInsets.symmetric(
                        //     horizontal: 12,
                        //   ),
                        //   leading: Icon(
                        //     Icons.send_time_extension,
                        //     color: Theme.of(context).iconTheme.color,
                        //   ),
                        //   title: Text(
                        //     "Gesendete Aufnahmen",
                        //     style: TextStyle(
                        //       fontSize: 14,
                        //       color:
                        //           Theme.of(
                        //             context,
                        //           ).textTheme.bodyLarge?.color ??
                        //           Colors.black,
                        //     ),
                        //   ),
                        //   trailing: Icon(
                        //     Icons.arrow_forward_ios,
                        //     size: 16,
                        //     color: Theme.of(context).iconTheme.color,
                        //   ),
                        //   onTap: () => Navigator.of(context).push(
                        //     MaterialPageRoute(
                        //       builder: (_) => const SendRecordingsScreen(),
                        //     ),
                        //   ),
                        // ),
                        const Divider(height: 1, indent: 17, endIndent: 16),
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          leading: Icon(
                            Icons.link,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          title: Text(
                            "Übereinstimmungen",
                            style: TextStyle(
                              fontSize: 14,
                              color:
                                  Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color ??
                                  Colors.black,
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const UebereinstimmungenScreen(),
                            ),
                          ),
                        ),
                        // ListTile(
                        //   dense: true,
                        //   contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        //   leading: Icon(
                        //     Icons.bookmark,
                        //     color: Theme.of(context).iconTheme.color,
                        //   ),
                        //   title: Text(
                        //     "Gespeichert",
                        //     style: TextStyle(
                        //       fontSize: 14,
                        //       color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                        //     ),
                        //   ),
                        //   trailing: Icon(
                        //     Icons.arrow_forward_ios,
                        //     size: 16,
                        //     color: Theme.of(context).iconTheme.color,
                        //   ),
                        //   onTap: () => Navigator.of(context).push(
                        //     MaterialPageRoute(
                        //       builder: (_) => SavedFavoritesScreen(),
                        //     ),
                        //   ),
                        // ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Neue Karte: Über die App
                  Card(
                    elevation: 0,
                    color: Theme.of(context).cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      leading: Icon(
                        Icons.info,
                        color: Theme.of(context).iconTheme.color,
                      ),
                      title: Text(
                        "Über die App",
                        style: TextStyle(
                          fontSize: 14,
                          color:
                              Theme.of(context).textTheme.bodyLarge?.color ??
                              Colors.black,
                        ),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Theme.of(context).iconTheme.color,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AboutScreen()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // "Auch von PHONĒ" Titel
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      "Auch von PHONĒ",
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    color: Theme.of(context).cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          leading: SizedBox(
                            width: 20,
                            height: 20,
                            child: SvgPicture.asset(
                              'assets/icons/instagram.svg',
                              width: 20,
                              height: 20,
                              fit: BoxFit.contain,
                              color: Theme.of(context).iconTheme.color,
                            ),
                          ),
                          title: Text(
                            "Instagram",
                            style: TextStyle(
                              fontSize: 14,
                              color:
                                  Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color ??
                                  Colors.black,
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Theme.of(context).iconTheme.color,
                          ),
                          onTap: () {
                            launchUrl(
                              Uri.parse(
                                'https://www.instagram.com/phoneapp.de?igsh=MWVpNm8wNnV2aWZnMg==',
                              ),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
