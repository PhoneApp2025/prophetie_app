import 'package:flutter/material.dart';
import 'package:prophetie_app/screens/auth_gate.dart';
import 'package:prophetie_app/screens/register_screen.dart';

class PhoneHeader extends StatelessWidget {
  final bool showLogo;
  const PhoneHeader({this.showLogo = true, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logo = showLogo
        ? Image.asset('assets/images/logo_schrift_weis.png', height: 48)
        : SizedBox.shrink();
    final userImages = [
      'assets/images/user1.png',
      'assets/images/user1.png',
      'assets/images/user1.png',
    ];
    return Column(
      children: [
        if (showLogo) ...[Center(child: logo), const SizedBox(height: 8)],
        Text(
          'Dein digitales Journal für Prophetien & Träume',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SizedBox(
                height: 40,
                width: 72,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Positioned(
                      left: 0,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundImage: AssetImage(userImages[0]),
                        backgroundColor: Colors.white,
                      ),
                    ),
                    Positioned(
                      left: 20,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundImage: AssetImage(userImages[1]),
                        backgroundColor: Colors.white,
                      ),
                    ),
                    Positioned(
                      left: 40,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundImage: AssetImage(userImages[2]),
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'von Gemeinden benutzt',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController pageController = PageController();
  int currentPage = 0;

  double _buttonOpacity = 0;
  double _contentOpacity = 0;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _buttonOpacity = 1);
      Future.delayed(const Duration(milliseconds: 420), () {
        if (mounted) setState(() => _contentOpacity = 1);
      });
    });
  }

  final List<Map<String, String>> pages = [
    {
      'title': 'Gott hat gesprochen – du willst es nie verlieren',
      'subtitle':
          'Alle Eingebungen, Träume und Worte an einem Ort – sicher, auffindbar, jederzeit verfügbar.',
      'image': 'assets/images/onboarding_1.png',
    },
    {
      'title': 'Sprich. Hör. Speichere. Teile.',
      'subtitle':
          'Halte fest, was der Himmel über dein Leben spricht. Ob Vision oder Traum – nimm es auf, speichere es, teile es. Vergiss nie wieder, was Gott sagt.',
      'image': 'assets/images/onboarding_2.png',
    },
    {
      'title': 'Gott war nicht leise – du hast nur vergessen',
      'subtitle':
          'Erkenne Muster, finde Bestätigung und sieh, wie sich Prophetien erfüllen. Rückblick, der stärkt.',
      'image': 'assets/images/onboarding_3.png',
    },
  ];

  void onPageChanged(int index) {
    setState(() {
      currentPage = index;
    });
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(pages.length, (index) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: currentPage == index ? 16 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: currentPage == index
                ? const Color(0xFFFF2C55)
                : Colors.white,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Höhe wie auf Login: PhoneHeader an exakt gleicher Y-Position
    const double headerTop = 68;

    final screenHeight = MediaQuery.of(context).size.height;
    final isLargeScreen = screenHeight > 700;
    final indicatorSpacing = isLargeScreen ? 0.0 : 10.0;
    final bottomIndicatorSpacing = isLargeScreen ? 25.0 : 30.0;
    final headerTopPosition = headerTop;
    final contentSectionHeight = screenHeight - headerTopPosition;

    final isSmallScreen = screenHeight < 600;
    final imageHeight = isSmallScreen
        ? screenHeight * 0.18
        : screenHeight * 0.23;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // PhoneHeader oben an gleicher Stelle wie auf LoginScreen
          Positioned(
            top: headerTop,
            left: 0,
            right: 0,
            child: const PhoneHeader(),
          ),
          // Onboarding-Content darunter
          Positioned.fill(
            top: headerTop + 115, // Abstand unterhalb Header
            child: Column(
              children: [
                // Content (PageView + Indikator) mit gestaffeltem Fade
                Expanded(
                  child: AnimatedOpacity(
                    opacity: _contentOpacity,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeInOut,
                    child: Column(
                      children: [
                        Expanded(
                          child: PageView.builder(
                            controller: pageController,
                            itemCount: pages.length,
                            onPageChanged: onPageChanged,
                            itemBuilder: (context, index) {
                              final page = pages[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 30.0,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (page['image'] != null)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: Image.asset(
                                          page['image']!,
                                          fit: BoxFit.contain,
                                          height: imageHeight,
                                        ),
                                      ),
                                    const SizedBox(height: 26),
                                    Text(
                                      page['title'] ?? '',
                                      style: TextStyle(
                                        fontSize: MediaQuery.of(context).size.width > 600 ? 30 : 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 13),
                                    Text(
                                      page['subtitle'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: Colors.white70,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(height: indicatorSpacing),
                        _buildPageIndicator(),
                        SizedBox(height: bottomIndicatorSpacing),
                      ],
                    ),
                  ),
                ),
                // Buttons mit Fade
                AnimatedOpacity(
                  opacity: _buttonOpacity,
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeInOut,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36.0),
                    child: Column(
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          onPressed: () {
                            if (currentPage < pages.length - 1) {
                              pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            } else {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            }
                          },
                          child: const Text(
                            'Jetzt starten',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                          ),
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const AuthGate(),
                              ),
                            );
                          },
                          child: const Text('Ich habe schon einen Account'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
