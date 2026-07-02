import 'package:flutter/material.dart';
import '/features/home/pages/home_page.dart';

void main() {
  runApp(const GestureApp());
}

class GestureApp extends StatelessWidget {
  const GestureApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "AI Cucumber Detection",
      theme: ThemeData(useMaterial3: true, fontFamily: "Roboto"),
      home: const HomePage(),
    );
  }
}
