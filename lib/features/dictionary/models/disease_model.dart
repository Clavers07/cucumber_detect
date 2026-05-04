class DiseaseModel {
  final String id;
  final String nama;
  final String namaLatin;
  final String kategori;
  final String deskripsi;
  final List<String> ciriCiri;
  final String penyebab;
  final String penanganan;
  final String pencegahan;

  DiseaseModel({
    required this.id,
    required this.nama,
    required this.namaLatin,
    required this.kategori,
    required this.deskripsi,
    required this.ciriCiri,
    required this.penyebab,
    required this.penanganan,
    required this.pencegahan,
  });

  factory DiseaseModel.fromJson(Map<String, dynamic> json) {
    return DiseaseModel(
      id: json['id'] ?? '',
      nama: json['nama'] ?? '',
      namaLatin: json['nama_latin'] ?? '',
      kategori: json['kategori'] ?? '',
      deskripsi: json['deskripsi'] ?? '',
      ciriCiri: List<String>.from(json['ciri_ciri'] ?? []),
      penyebab: json['penyebab'] ?? '',
      penanganan: json['penanganan'] ?? '',
      pencegahan: json['pencegahan'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nama': nama,
      'nama_latin': namaLatin,
      'kategori': kategori,
      'deskripsi': deskripsi,
      'ciri_ciri': ciriCiri,
      'penyebab': penyebab,
      'penanganan': penanganan,
      'pencegahan': pencegahan,
    };
  }

  // Path ke gambar sesuai id, ekstensi defaultnya jpg
  String get imagePath => 'assets/images/diseases/$id.jpg';
}
