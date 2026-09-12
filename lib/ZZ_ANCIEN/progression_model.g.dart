// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'progression_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProgressionCoursMathAdapter extends TypeAdapter<ProgressionCoursMath> {
  @override
  final int typeId = 10;

  @override
  ProgressionCoursMath read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ProgressionCoursMath(
      leconId: fields[0] as String,
      partieIndex: fields[1] as int,
      etapeIndex: fields[2] as int,
      rythme: fields[3] as String,
      dernierScore: fields[4] as double,
      erreursTypes: (fields[5] as List).cast<String>(),
      derniereMaj: fields[6] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, ProgressionCoursMath obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.leconId)
      ..writeByte(1)
      ..write(obj.partieIndex)
      ..writeByte(2)
      ..write(obj.etapeIndex)
      ..writeByte(3)
      ..write(obj.rythme)
      ..writeByte(4)
      ..write(obj.dernierScore)
      ..writeByte(5)
      ..write(obj.erreursTypes)
      ..writeByte(6)
      ..write(obj.derniereMaj);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgressionCoursMathAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
