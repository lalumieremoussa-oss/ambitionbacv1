import 'package:hive/hive.dart';

part 'progression_model.g.dart';

@HiveType(typeId: 10)
class ProgressionCoursMath {
  @HiveField(0)
  String leconId;

  @HiveField(1)
  int partieIndex;

  @HiveField(2)
  int etapeIndex;

  @HiveField(3)
  String rythme;

  @HiveField(4)
  double dernierScore;

  @HiveField(5)
  List<String> erreursTypes;

  @HiveField(6)
  DateTime derniereMaj;

  ProgressionCoursMath({
    required this.leconId,
    this.partieIndex = 0,
    this.etapeIndex = 0,
    this.rythme = "moyen",
    this.dernierScore = 0,
    this.erreursTypes = const [],
    required this.derniereMaj,
  });

  // Méthode pour créer une copie avec des valeurs modifiées
  ProgressionCoursMath copyWith({
    String? leconId,
    int? partieIndex,
    int? etapeIndex,
    String? rythme,
    double? dernierScore,
    List<String>? erreursTypes,
    DateTime? derniereMaj,
  }) {
    return ProgressionCoursMath(
      leconId: leconId ?? this.leconId,
      partieIndex: partieIndex ?? this.partieIndex,
      etapeIndex: etapeIndex ?? this.etapeIndex,
      rythme: rythme ?? this.rythme,
      dernierScore: dernierScore ?? this.dernierScore,
      erreursTypes: erreursTypes ?? this.erreursTypes,
      derniereMaj: derniereMaj ?? this.derniereMaj,
    );
  }

  @override
  String toString() {
    return 'ProgressionCoursMath{leconId: $leconId, partieIndex: $partieIndex, etapeIndex: $etapeIndex, rythme: $rythme, dernierScore: $dernierScore, erreursTypes: $erreursTypes, derniereMaj: $derniereMaj}';
  }
}
