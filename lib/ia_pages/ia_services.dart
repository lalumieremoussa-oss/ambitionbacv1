// 📁 lib/ia_pages/ia_service.dart

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ===============================================================
/// IA SERVICE
/// ===============================================================
///
/// Architecture :
///
/// Flutter
///    ↓
/// IaService
///    ↓
/// Supabase Edge Function
///    ↓
/// ai_model_config
///    ↓
/// Fournisseur actif
///    ├── DeepSeek
///    ├── Qwen
///    ├── OpenAI
///    └── Gemini
///
/// IMPORTANT :
/// - Flutter NE LIT PAS api_key_secret.
/// - Les clés API restent côté Edge Function.
/// - Le choix du fournisseur/modèle se fait côté serveur.
/// - La table ai_model_config permet de changer de fournisseur
///   sans publier une nouvelle version de l'application.
/// - L'utilisateur est identifié par son MATRICULE (pas via Supabase Auth).
/// - Les prompts système sont désormais stockés dans la table `system_prompt`
///   et chargés côté Edge Function via `prompt_key`.
/// ===============================================================

class IaService {
  IaService._();

  static final IaService instance = IaService._();

  factory IaService() => instance;

  final SupabaseClient _supabase = Supabase.instance.client;

  static const String _edgeFunctionName = 'ia-chat';

  // ===============================================================
  // RÉCUPÉRATION DU MATRICULE
  // ===============================================================

  /// Récupère le matricule depuis SharedPreferences.
  Future<String?> _getMatricule() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('matricule');
  }

  // ===============================================================
  // CHAT COMPLETION AVEC PROMPT_KEY OU SYSTEM_PROMPT
  // ===============================================================

  /// Effectue un appel à l'Edge Function `ia-chat`.
  ///
  /// - Soit on fournit `systemPrompt` (contenu textuel complet),
  /// - Soit on fournit `promptKey` (clé dans la table `system_prompt`),
  ///   et c'est l'Edge Function qui récupère le contenu en base.
  ///
  /// Les deux ne doivent pas être utilisés en même temps.
  Future<String> chatCompletion({
    String? systemPrompt,
    String? promptKey,
    required String userPrompt,
    double? temperature,
    int? maxTokens,
  }) async {
    if (userPrompt.trim().isEmpty) {
      throw const IaServiceException('Le message utilisateur est vide.');
    }
    if (systemPrompt == null && promptKey == null) {
      throw const IaServiceException(
          'Il faut fournir soit systemPrompt soit promptKey.');
    }
    if (systemPrompt != null && promptKey != null) {
      throw const IaServiceException(
          'Fournir soit systemPrompt soit promptKey, pas les deux.');
    }

    final matricule = await _getMatricule();
    if (matricule == null || matricule.isEmpty) {
      throw const IaServiceException(
        'Matricule introuvable. Veuillez vous reconnecter.',
      );
    }

    try {
      final Map<String, dynamic> body = {
        'user_prompt': userPrompt.trim(),
        'matricule': matricule,
      };
      if (systemPrompt != null) {
        body['system_prompt'] = systemPrompt.trim();
      } else {
        body['prompt_key'] = promptKey!.trim();
      }
      if (temperature != null) body['temperature'] = temperature;
      if (maxTokens != null) body['max_tokens'] = maxTokens;

      final response = await _supabase.functions.invoke(
        _edgeFunctionName,
        body: body,
      );

      if (response.data == null) {
        throw const IaServiceException(
          'Le serveur IA n’a retourné aucune donnée.',
        );
      }

      return _extractContent(response.data);
    } on FunctionException catch (e) {
      throw IaServiceException(_extractFunctionError(e));
    } on PostgrestException catch (e) {
      throw IaServiceException(e.message);
    } on IaServiceException {
      rethrow;
    } catch (e) {
      throw IaServiceException(
        'Impossible de contacter le service IA.',
        originalError: e,
      );
    }
  }

  // ===============================================================
  // CHAT JSON (raccourci pour réponse JSON)
  // ===============================================================

  /// Version de `chatCompletion` qui parse automatiquement la réponse en JSON.
  ///
  /// Accepte les mêmes paramètres que `chatCompletion` (avec ou sans promptKey).
  Future<Map<String, dynamic>> chatJson({
    String? systemPrompt,
    String? promptKey,
    required String userPrompt,
    double? temperature,
    int? maxTokens,
  }) async {
    final raw = await chatCompletion(
      systemPrompt: systemPrompt,
      promptKey: promptKey,
      userPrompt: userPrompt,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    return _decodeJsonResponse(raw);
  }

  // ===============================================================
  // GÉNÉRATION DE DISSERTATION (promptKey obligatoire)
  // ===============================================================

  /// Génère un plan de dissertation à partir d'un sujet.
  ///
  /// [promptKey] : clé du prompt système dans la table `system_prompt`.
  /// [sujet] : sujet de la dissertation.
  Future<Map<String, dynamic>> generateDissertation({
    required String promptKey,
    required String sujet,
  }) async {
    if (sujet.trim().isEmpty) {
      throw const IaServiceException(
          'Veuillez saisir un sujet de dissertation.');
    }
    return chatJson(
      promptKey: promptKey,
      userPrompt: sujet.trim(),
      temperature: 0.20,
      maxTokens: 4000,
    );
  }

  // ===============================================================
  // EXTRACTION DE LA RÉPONSE (gère différents formats)
  // ===============================================================

  String _extractContent(dynamic data) {
    dynamic payload = data;

    if (payload is Map<String, dynamic>) {
      if (payload.containsKey('error')) {
        throw IaServiceException(
          _stringValue(payload['error']) ?? 'Une erreur IA est survenue.',
        );
      }

      // Si l'Edge Function renvoie un message d'erreur explicite
      if (payload.containsKey('message') &&
          payload['message'] is String &&
          payload['content'] == null &&
          payload['result'] == null) {
        final message = payload['message'];
        if (payload['success'] == false) {
          throw IaServiceException(message.toString());
        }
      }

      // Recherche du contenu principal
      if (payload.containsKey('content')) {
        return _normalizeContent(payload['content']);
      }
      if (payload.containsKey('result')) {
        return _normalizeContent(payload['result']);
      }
      if (payload.containsKey('response')) {
        return _normalizeContent(payload['response']);
      }

      // Sinon, on renvoie tout l'objet en JSON
      return jsonEncode(payload);
    }

    if (payload is String) {
      final value = payload.trim();
      if (value.isEmpty) {
        throw const IaServiceException('La réponse du serveur IA est vide.');
      }
      return value;
    }

    throw IaServiceException(
      'Format de réponse IA inattendu : ${payload.runtimeType}',
    );
  }

  // ===============================================================
  // NORMALISATION DU CONTENU
  // ===============================================================

  String _normalizeContent(dynamic content) {
    if (content == null) {
      throw const IaServiceException(
          'Le modèle IA a retourné un contenu vide.');
    }
    if (content is String) {
      final value = content.trim();
      if (value.isEmpty) {
        throw const IaServiceException(
            'Le modèle IA a retourné un contenu vide.');
      }
      return value;
    }
    if (content is Map<String, dynamic>) {
      return jsonEncode(content);
    }
    if (content is List) {
      return jsonEncode(content);
    }
    return content.toString();
  }

  // ===============================================================
  // DÉCODAGE JSON (avec nettoyage des balises markdown)
  // ===============================================================

  Map<String, dynamic> _decodeJsonResponse(String raw) {
    String cleaned = raw.trim();

    // Nettoyer les éventuelles balises Markdown
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7).trim();
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3).trim();
      }
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3).trim();
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3).trim();
      }
    }

    // Supprimer les caractères de contrôle problématiques
    cleaned =
        cleaned.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw const IaServiceException(
          'La réponse IA n’est pas un objet JSON valide.');
    } on FormatException catch (e) {
      throw IaServiceException(
        'Le modèle IA a retourné une réponse qui n’est pas un JSON valide.',
        originalError: e,
      );
    }
  }

  // ===============================================================
  // EXTRACTION DES ERREURS DE L'EDGE FUNCTION
  // ===============================================================

  String _extractFunctionError(FunctionException error) {
    final details = error.details;
    if (details is Map) {
      final message = details['message'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
      final errorMessage = details['error'];
      if (errorMessage != null && errorMessage.toString().trim().isNotEmpty) {
        return errorMessage.toString();
      }
    }
    if (details != null) {
      final value = details.toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return error.reasonPhrase ??
        'Le service IA est temporairement indisponible.';
  }

  // ===============================================================
  // UTILITAIRE
  // ===============================================================

  String? _stringValue(dynamic value) {
    if (value == null) return null;
    final result = value.toString().trim();
    if (result.isEmpty) return null;
    return result;
  }
}

// ===============================================================
// EXCEPTION IA
// ===============================================================

class IaServiceException implements Exception {
  final String message;
  final Object? originalError;

  const IaServiceException(this.message, {this.originalError});

  @override
  String toString() => message;
}
