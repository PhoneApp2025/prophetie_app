import 'package:flutter/material.dart';

class AufnahmeScreen extends StatefulWidget {
  const AufnahmeScreen({super.key});

  @override
  State<AufnahmeScreen> createState() => _AufnahmeScreenState();
}

class _AufnahmeScreenState extends State<AufnahmeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Aufnahme")),
      body: const Center(child: Text("Aufnahmescreen")),
    );
  }
}
