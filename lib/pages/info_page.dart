import 'package:flutter/material.dart';
import 'dart:ui';

class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  final List<Map<String, String>> signList = const [
    {"label": "Batang Sawit Sehat", "desc": "-"},
    {"label": "Buah Sawit Sehat", "desc": "-"},
    {"label": "Busuk Pucuk", "desc": "-"},
    {"label": "Daun Sehat", "desc": "-"},
    {"label": "Hama Tikus", "desc": "-"},
    {"label": "Jamur Ganoderma", "desc": "-"},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text("Katalog Penyakit"), backgroundColor: Colors.transparent, elevation: 0),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xff0f172a), Color(0xff1e293b)]),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 120, 20, 20),
          itemCount: signList.length,
          itemBuilder: (context, index) {
            return Container(
              margin: const EdgeInsets.only(bottom: 15),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.cyanAccent.withOpacity(0.2),
                        child: Text("${index + 1}", style: const TextStyle(color: Colors.cyanAccent)),
                      ),
                      title: Text(signList[index]['label']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text(signList[index]['desc']!, style: const TextStyle(color: Colors.white70)),
                      trailing: const Icon(Icons.info_outline, color: Colors.white38),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}