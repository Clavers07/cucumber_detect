import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/disease_model.dart';

class DictionaryService {
  Future<List<DiseaseModel>> loadDiseases() async {
    try {
      final String response = await rootBundle.loadString('assets/data/diseases.json');
      final List<dynamic> data = json.decode(response);
      return data.map((json) => DiseaseModel.fromJson(json)).toList();
    } catch (e) {
      print('Error loading diseases: $e');
      return [];
    }
  }

  Future<List<DiseaseModel>> searchDiseases(String query) async {
    final allDiseases = await loadDiseases();
    if (query.isEmpty) {
      return allDiseases;
    }
    
    final lowerQuery = query.toLowerCase();
    return allDiseases.where((disease) {
      return disease.nama.toLowerCase().contains(lowerQuery) ||
             disease.deskripsi.toLowerCase().contains(lowerQuery) ||
             disease.kategori.toLowerCase().contains(lowerQuery) ||
             disease.ciriCiri.any((ciri) => ciri.toLowerCase().contains(lowerQuery));
    }).toList();
  }
}
