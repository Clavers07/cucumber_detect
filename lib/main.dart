import 'package:flutter/material.dart';
import 'features/splash/pages/splash_page.dart';

void main() {
  runApp(const SawitUpApp());
}

class SawitUpApp extends StatelessWidget {
  const SawitUpApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Sawit Up",
      theme: ThemeData(useMaterial3: true, fontFamily: "Roboto"),
      home: const SplashPage(),
    );
  }
}
