import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'widgets/update_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(
    MultiProvider(
      providers: [
        // your providers here
      ],
      child: UpdateGate(child: const MyApp()),
    ),
  );
}