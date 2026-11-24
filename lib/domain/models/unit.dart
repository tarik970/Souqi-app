class Unit {
  const Unit({
    this.id,
    required this.nameAr,
    required this.nameEn,
    this.isPreset = false,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final int? id;
  final String nameAr;
  final String nameEn;
  final bool isPreset;
  final bool isActive;
  final int sortOrder;

  String nameFor(String languageCode) =>
      languageCode == 'ar' ? nameAr : nameEn;

  static Unit fromMap(Map<String, Object?> map) {
    return Unit(
      id: map['id'] as int,
      nameAr: map['name_ar'] as String,
      nameEn: map['name_en'] as String,
      isPreset: map['is_preset'] == 1,
      isActive: map['is_active'] == 1,
      sortOrder: map['sort_order'] as int,
    );
  }

  Map<String, Object?> toMap() => {
        'name_ar': nameAr,
        'name_en': nameEn,
        'is_preset': isPreset ? 1 : 0,
        'is_active': isActive ? 1 : 0,
        'sort_order': sortOrder,
      };
}
