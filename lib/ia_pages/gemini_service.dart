import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CoachAiException implements Exception {
  final String message;
  final String? code;
  CoachAiException(this.message, {this.code});
  @override
  String toString() => message;
}

class CoachAudioResponse {
  final Uint8List wavBytes;
  final String? inputText;
  final String? outputText;
  final int remaining;

  CoachAudioResponse({
    required this.wavBytes,
    required this.remaining,
    this.inputText,
    this.outputText,
  });
}

class ContextTurn {
  final String role;
  final String text;
  ContextTurn({required this.role, required this.text});
  Map<String, String> toJson() => {'role': role, 'text': text};
}

class CoachAiService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static const String _functionName = 'coach-ai';

  static const Duration _clientTimeout = Duration(seconds: 160);

  static Future<CoachAudioResponse> sendAudio({
    required Uint8List pcm16Mono16k,
    required String systemPrompt,
    required String matricule,
    required String professor,
    required String level,
    String? language,
    List<ContextTurn>? priorContext,
  }) async {
    if (pcm16Mono16k.isEmpty) {
      throw CoachAiException('Aucun audio à envoyer.');
    }
    if (matricule.trim().isEmpty) {
      throw CoachAiException('Utilisateur non identifié (matricule manquant).');
    }

    final requestBody = {
      'matricule': matricule,
      'audioBase64': base64Encode(pcm16Mono16k),
      'systemPrompt': systemPrompt,
      'professor': professor,
      'level': level,
      if (language != null) 'language': language,
      if (priorContext != null && priorContext.isNotEmpty)
        'priorContext': priorContext.map((t) => t.toJson()).toList(),
    };

    FunctionResponse response;
    try {
      response = await _supabase.functions
          .invoke(_functionName, body: requestBody)
          .timeout(_clientTimeout);
    } on TimeoutException {
      throw CoachAiException(
        'Le coach met trop de temps à répondre. Réessayez dans un instant.',
        code: 'CLIENT_TIMEOUT',
      );
    } on SocketException catch (e) {
      debugPrint('CoachAi SocketException: $e');
      throw CoachAiException(
        'Pas de connexion internet. Vérifiez votre réseau.',
        code: 'NO_NETWORK',
      );
    } on FunctionException catch (e) {
      final details = e.details;
      String msg = 'Erreur inconnue du coach IA.';
      String? code;
      if (details is Map) {
        msg = details['error']?.toString() ?? msg;
        code = details['code']?.toString();
      } else if (e.reasonPhrase != null && e.reasonPhrase!.isNotEmpty) {
        msg = e.reasonPhrase!;
      }
      debugPrint('CoachAi FunctionException [$code]: $msg');
      throw CoachAiException(msg, code: code);
    } catch (e, st) {
      debugPrint('CoachAi erreur inattendue: $e\n$st');
      throw CoachAiException(
        'Erreur technique du coach IA : $e',
        code: 'UNEXPECTED',
      );
    }

    Map<String, dynamic> data;
    final raw = response.data;
    if (raw is Map<String, dynamic>) {
      data = raw;
    } else if (raw is String) {
      try {
        data = json.decode(raw) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('CoachAi: réponse JSON invalide: $raw ($e)');
        throw CoachAiException('Réponse invalide du serveur.',
            code: 'BAD_JSON');
      }
    } else {
      debugPrint('CoachAi: type de réponse inattendu: ${raw.runtimeType}');
      throw CoachAiException('Réponse invalide du serveur.',
          code: 'BAD_RESPONSE_TYPE');
    }

    if (data['success'] == false) {
      final errorMsg =
          data['error']?.toString() ?? 'Erreur inconnue du coach IA.';
      throw CoachAiException(errorMsg, code: data['code']?.toString());
    }

    final audioB64 = data['audioBase64'] as String?;
    if (audioB64 == null || audioB64.isEmpty) {
      throw CoachAiException('Le coach IA n\'a renvoyé aucun audio.',
          code: 'NO_AUDIO');
    }

    return CoachAudioResponse(
      wavBytes: base64Decode(audioB64),
      remaining: (data['remaining'] as num?)?.toInt() ?? 0,
      inputText: data['inputText'] as String?,
      outputText: data['outputText'] as String?,
    );
  }

  static Uint8List extractPcmFromWav(Uint8List wavBytes) {
    if (wavBytes.length < 12) return wavBytes;
    final isRiff = wavBytes[0] == 0x52 &&
        wavBytes[1] == 0x49 &&
        wavBytes[2] == 0x46 &&
        wavBytes[3] == 0x46;
    if (!isRiff) return wavBytes;

    int offset = 12;
    while (offset + 8 <= wavBytes.length) {
      final chunkId =
          String.fromCharCodes(wavBytes.sublist(offset, offset + 4));
      final chunkSize = wavBytes[offset + 4] |
          (wavBytes[offset + 5] << 8) |
          (wavBytes[offset + 6] << 16) |
          (wavBytes[offset + 7] << 24);
      final dataStart = offset + 8;
      if (chunkId == 'data') {
        final end = (dataStart + chunkSize) <= wavBytes.length
            ? dataStart + chunkSize
            : wavBytes.length;
        return wavBytes.sublist(dataStart, end);
      }
      offset = dataStart + chunkSize + (chunkSize % 2);
    }
    return wavBytes;
  }
}
