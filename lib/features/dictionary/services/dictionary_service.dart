import '../models/disease_model.dart';
import '../../../core/database/database_service.dart';

class DictionaryService {
  Future<List<DiseaseModel>> loadDiseases() async {
    try {
      return await DatabaseService.instance.getAllDiseases();
    } catch (e) {
      print('Error loading diseases from DB: $e');
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
