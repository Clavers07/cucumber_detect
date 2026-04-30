import 'package:flutter/material.dart';
import 'dart:ui';
import 'info_page.dart';
import 'detection_page.dart';
import '../features/home/pages/home_page.dart' as new_home;
import '../features/detection/pages/detection_page.dart' as new_detection;

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Widget glassMenuCard(BuildContext context, String title, IconData icon, Color color, Widget page) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
              gradient: LinearGradient(
                colors: [Colors.white.withOpacity(0.2), Colors.white.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 50, color: color),
                const SizedBox(height: 15),
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xff0f172a), Color(0xff334155), Color(0xff1e293b)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("AI Detect", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                const Text("Pendeteksi Penyakit Sawit", style: TextStyle(fontSize: 16, color: Colors.white70)),
                const SizedBox(height: 40),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                    children: [
                      glassMenuCard(context, "Daftar Kelas", Icons.menu_book, Colors.cyanAccent, const InfoPage()),
                      glassMenuCard(context, "Deteksi Kamera", Icons.camera_enhance, Colors.greenAccent, const DetectionPage()),
                      glassMenuCard(context, "New Home", Icons.home, Colors.greenAccent, const new_home.HomePage()),
                      // glassMenuCard(context, "New Camera", Icons.camera, Colors.greenAccent, const new_detection.DetectionPage()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}