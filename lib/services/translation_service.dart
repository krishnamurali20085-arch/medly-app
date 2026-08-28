import 'dart:convert';
import 'package:http/http.dart' as http;

/// Translation service using Google Translate (free API endpoint).
/// Translates AI responses to the user's selected language.
class TranslationService {
  /// Map from our language names to Google Translate language codes
  static const Map<String, String> _languageCodes = {
    'English': 'en',
    'Tamil': 'ta',
    'Telugu': 'te',
    'Kannada': 'kn',
    'Malayalam': 'ml',
    'Hindi': 'hi',
    'Marathi': 'mr',
    'Urdu': 'ur',
    'French': 'fr',
    'Japanese': 'ja',
  };

  /// Translate text from English to the target language.
  /// Returns the translated text, or the original text if translation fails.
  static Future<String> translate({
    required String text,
    required String targetLanguage,
    String sourceLanguage = 'en',
  }) async {
    if (targetLanguage == 'English' || text.trim().isEmpty) {
      return text;
    }

    final targetCode = _languageCodes[targetLanguage];
    if (targetCode == null) return text;

    final sourceCode = _languageCodes[sourceLanguage] ?? 'en';

    try {
      // Use Google Translate's free endpoint
      final url = Uri.parse(
        'https://translate.googleapis.com/translate_a/single'
        '?client=gtx'
        '&sl=$sourceCode'
        '&tl=$targetCode'
        '&dt=t'
        '&q=${Uri.encodeComponent(text)}',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Response format: [[["translated text","original text",null,null,10]],null,"en"]
        if (data is List && data.isNotEmpty && data[0] is List) {
          final translations = data[0] as List;
          final buffer = StringBuffer();
          for (final part in translations) {
            if (part is List && part.isNotEmpty) {
              buffer.write(part[0]?.toString() ?? '');
            }
          }
          final result = buffer.toString();
          if (result.isNotEmpty) return result;
        }
      }
    } catch (e) {
      print('[Translation] Error: $e');
    }

    // Return original text if translation fails
    return text;
  }

  /// Get the language code for TTS
  static String getLanguageCode(String language) {
    return _languageCodes[language] ?? 'en';
  }

  /// Get all supported languages
  static List<String> get supportedLanguages => _languageCodes.keys.toList();
}
