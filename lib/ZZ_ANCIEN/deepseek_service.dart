import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DeepSeekService {
  static final DeepSeekService _instance = DeepSeekService._internal();
  factory DeepSeekService() => _instance;
  DeepSeekService._internal();

  String get _apiKey => dotenv.env['DEEPSEEK_API_KEY'] ?? '';
  static const String _baseUrl = 'https://api.deepseek.com/v1';

  // Choix du modèle
  static const String _model = 'deepseek-v4-flash';

  Future<String> chatCompletion({
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.7,
    int maxTokens = 2000,
  }) async {
    if (_apiKey.isEmpty) {
      return "⚠️ Clé API DeepSeek manquante. Vérifiez votre fichier .env";
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          'temperature': temperature,
          'max_tokens': maxTokens,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        if (response.statusCode == 401) {
          return "❌ Clé API invalide. Vérifiez votre clé DeepSeek.";
        } else if (response.statusCode == 429) {
          return "⏳ Trop de requêtes. Attendez quelques secondes.";
        } else if (response.statusCode == 400) {
          return "❌ Erreur de requête: ${response.body}";
        } else {
          return "❌ Erreur API (${response.statusCode}): ${response.body}";
        }
      }
    } catch (e) {
      return "❌ Erreur de connexion: $e\nVérifiez votre connexion internet.";
    }
  }

  Stream<String> chatCompletionStream({
    required String systemPrompt,
    required String userPrompt,
    double temperature = 0.7,
    int maxTokens = 2000,
  }) async* {
    if (_apiKey.isEmpty) {
      yield "⚠️ Clé API DeepSeek manquante.";
      return;
    }

    try {
      final request = http.Request(
        'POST',
        Uri.parse('$_baseUrl/chat/completions'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.headers['Authorization'] = 'Bearer $_apiKey';
      request.body = jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': temperature,
        'max_tokens': maxTokens,
        'stream': true,
      });

      final response = await request.send();

      await for (var chunk in response.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n');
        for (var line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6);
            if (data == '[DONE]') break;
            try {
              final jsonData = jsonDecode(data);
              final content = jsonData['choices'][0]['delta']['content'];
              if (content != null) {
                yield content;
              }
            } catch (e) {}
          }
        }
      }
    } catch (e) {
      yield "❌ Erreur: $e";
    }
  }
}
