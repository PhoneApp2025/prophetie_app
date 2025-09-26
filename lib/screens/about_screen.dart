import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Über die App',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color:
                Theme.of(context).textTheme.titleLarge?.color ?? Colors.black,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Warum diese App?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color:
                      Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withOpacity(0.6) ??
                      Colors.grey,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            // Section: Warum diese App?
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 0),
                    Text(
                      'Mein Name ist Simon Nikel. Diese App ist aus einem Herzenswunsch heraus entstanden: Prophetien und Träume, die ich empfange, gut und strukturiert zu verwalten. Ich habe festgestellt, wie schnell Worte verloren gehen können – obwohl Gott so klar spricht.\n\n'
                      'Mit PHONĒ möchte ich dir ein Werkzeug geben, mit dem du deine prophetischen Eindrücke, Träume oder Botschaften sicher speichern und ordnen kannst. Diese App ist nicht zum Geldverdienen gedacht, sondern soll dir helfen, ein guter Verwalter dessen zu sein, was Gott dir oder durch dich spricht.',
                      style: TextStyle(
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                        fontFamily: 'Poppins',
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Warum der Name PHONĒ?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color:
                      Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withOpacity(0.6) ??
                      Colors.grey,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            // Section: Warum der Name PHONĒ?
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 0),
                    Text(
                      'PHONĒ (φωνή, ausgesprochen: "Fo-nä", Phone-nay) ist ein griechisches Wort aus dem Neuen Testament und bedeutet „Stimme“. Es stammt vom Verb φημί (phēmi), was „sprechen“, „sagen“ oder „offenbaren“ bedeutet. Das Wort wird häufig in Momenten verwendet, in denen Gott direkt spricht – etwa „Und siehe, eine Stimme (φωνή) aus dem Himmel sprach …“ (vgl. Matthäus 3,17).\n\n'
                      'Diese App trägt diesen Namen, weil sie Raum geben soll, Gottes Reden aufzunehmen, zu verwalten und festzuhalten. PHONĒ steht dabei nicht für ein Gerät, sondern für das Hören und das Erinnern an Gottes Stimme – so wie sie in Träumen, Eindrücken und prophetischen Worten zu uns kommt.',
                      style: TextStyle(
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                        fontFamily: 'Poppins',
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Warum kostet die App?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color:
                      Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withOpacity(0.6) ??
                      Colors.grey,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            // Section: Warum kostet die App 25€ im Jahr?
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 0),
                    Text(
                      'Die App verursacht laufende Kosten, z. B. für Server, Sicherheit und Weiterentwicklung. Deshalb gibt es eine kostenpflichtige Premium-Version, die hilft, diese Ausgaben zu decken.\n\n'
                      'Wenn du die App wertvoll findest, kannst du mit deinem Beitrag dazu beitragen, dass sie weiterhin gepflegt und verbessert wird. So bleibt PHONĒ für viele Menschen verfügbar und nachhaltig nutzbar.',
                      style: TextStyle(
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                        fontFamily: 'Poppins',
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Verbesserungsvorschläge',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color:
                      Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withOpacity(0.6) ??
                      Colors.grey,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            // Section: Verbesserungsvorschläge
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 0),
                    Text(
                      'Für Verbesserungsvorschläge: phone@simonnikel.de',
                      style: TextStyle(
                        color:
                            Theme.of(context).textTheme.bodyLarge?.color ??
                            Colors.black,
                        fontFamily: 'Poppins',
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
