import 'package:flutter/material.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            'Benachrichtigungen',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color:
                  Theme.of(context).textTheme.titleLarge?.color ?? Colors.black,
            ),
          ),
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          foregroundColor:
              Theme.of(context).appBarTheme.foregroundColor ?? Colors.black,
          elevation: 1,
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Text(
                'Hier erscheinen deine Benachrichtigungen.\n\n',
                style: TextStyle(
                  color:
                      Theme.of(context).textTheme.bodyLarge?.color ??
                      Colors.black,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
