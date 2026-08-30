import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../services/app_localizations.dart';

class SymptomCheckerPage extends StatefulWidget {
  const SymptomCheckerPage({super.key, required this.language});
  final String language;

  @override
  State<SymptomCheckerPage> createState() => _SymptomCheckerPageState();
}

class _SymptomCheckerPageState extends State<SymptomCheckerPage> {
  String _t(String v) => AppLocalizations(widget.language).text(v);
  
  File? _imageFile;
  bool _isAnalyzing = false;
  String? _result;
  String? _urgencyLevel;
  final TextEditingController _descriptionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  // Gemini API key (bundled in app)
  static const String _geminiApiKey = 'AIzaSyDummyReplaceMe';

  Future<void> _takePhoto() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (photo != null) {
      setState(() {
        _imageFile = File(photo.path);
        _result = null;
        _urgencyLevel = null;
      });
    }
  }

  Future<void> _pickFromGallery() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (photo != null) {
      setState(() {
        _imageFile = File(photo.path);
        _result = null;
        _urgencyLevel = null;
      });
    }
  }

  Future<void> _analyzeImage() async {
    if (_imageFile == null) return;

    setState(() {
      _isAnalyzing = true;
      _result = null;
      _urgencyLevel = null;
    });

    try {
      // Read image as bytes and encode to base64
      final bytes = await _imageFile!.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Determine language for response
      final langCode = _getLangCode(widget.language);
      final extraContext = _descriptionController.text.isNotEmpty
          ? '\n\nAdditional description from patient: "${_descriptionController.text}"'
          : '';

      final prompt = '''You are Medly, a medical AI assistant specializing in visual symptom analysis. 
A patient has shared a photo for you to examine.

Analyze the image and provide:
1. **What you observe**: Describe what you see in the image (skin condition, wound type, eye issue, etc.)
2. **Possible conditions**: List 2-3 possible conditions this could indicate
3. **Urgency level**: Classify as one of:
   - 🟢 LOW: Minor issue, home care possible
   - 🟡 MODERATE: Should see a doctor within 1-2 days
   - 🟠 HIGH: Seek medical attention today
   - 🔴 EMERGENCY: Go to ER immediately
4. **First aid steps**: Provide immediate care instructions
5. **When to see a doctor**: Specific warning signs that require professional help

$extraContext

IMPORTANT: 
- Respond entirely in ${widget.language} language (language code: $langCode)
- Be thorough but concise
- Include disclaimer: "This is AI-generated guidance, not a professional diagnosis. Always consult a healthcare provider."
- If the image is unclear or not a medical condition, say so politely.''';

      // Call Gemini API with image
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{
            'parts': [
              {'text': prompt},
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': base64Image,
                }
              }
            ]
          }],
          'generationConfig': {
            'temperature': 0.4,
            'maxOutputTokens': 1024,
          }
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
        if (text != null && text.isNotEmpty) {
          // Determine urgency from response
          String urgency = 'MODERATE';
          if (text.contains('🔴') || text.toUpperCase().contains('EMERGENCY')) {
            urgency = 'EMERGENCY';
          } else if (text.contains('🟠') || text.toUpperCase().contains('HIGH')) {
            urgency = 'HIGH';
          } else if (text.contains('🟡') || text.toUpperCase().contains('MODERATE')) {
            urgency = 'MODERATE';
          } else if (text.contains('🟢') || text.toUpperCase().contains('LOW')) {
            urgency = 'LOW';
          }

          setState(() {
            _result = text;
            _urgencyLevel = urgency;
            _isAnalyzing = false;
          });
          return;
        }
      }

      // If API fails, provide local fallback
      setState(() {
        _result = _getLocalFallback();
        _urgencyLevel = 'MODERATE';
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        _result = _getLocalFallback();
        _urgencyLevel = 'MODERATE';
        _isAnalyzing = false;
      });
    }
  }

  String _getLocalFallback() {
    return '''⚠️ ${_t('AI analysis unavailable offline')}

${_t('General guidance for skin/wound issues:')}

1. ${_t('Clean the area gently with clean water')}
2. ${_t('Apply antibiotic ointment if available')}
3. ${_t('Cover with a clean bandage if needed')}
4. ${_t('Monitor for signs of infection: redness, swelling, pus, fever')}

${_t('When to see a doctor:')}
- ${_t('Wound is deep or won\'t stop bleeding')}
- ${_t('Signs of infection appear')}
- ${_t('Condition worsens over time')}
- ${_t('You are unsure about the severity')}

⚠️ ${_t('This is general guidance only. Consult a healthcare professional for proper diagnosis.')}''';
  }

  String _getLangCode(String lang) {
    const codes = {
      'English': 'en', 'Tamil': 'ta', 'Telugu': 'te', 'Kannada': 'kn',
      'Malayalam': 'ml', 'Hindi': 'hi', 'Marathi': 'mr', 'Urdu': 'ur',
      'French': 'fr', 'Japanese': 'ja',
    };
    return codes[lang] ?? 'en';
  }

  Color _urgencyColor() {
    switch (_urgencyLevel) {
      case 'EMERGENCY': return Colors.red;
      case 'HIGH': return Colors.orange;
      case 'MODERATE': return Colors.amber;
      case 'LOW': return Colors.green;
      default: return Colors.grey;
    }
  }

  IconData _urgencyIcon() {
    switch (_urgencyLevel) {
      case 'EMERGENCY': return Icons.error_rounded;
      case 'HIGH': return Icons.warning_rounded;
      case 'MODERATE': return Icons.info_rounded;
      case 'LOW': return Icons.check_circle_rounded;
      default: return Icons.help_rounded;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_t('Symptom Checker')),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Photo section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2937) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.camera_alt_rounded, size: 48, color: Colors.teal.shade600),
                  const SizedBox(height: 8),
                  Text(_t('Take or upload a photo of the area'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(_t('Skin rash, wound, eye issue, etc.'),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isAnalyzing ? null : _takePhoto,
                          icon: const Icon(Icons.camera_alt, size: 18),
                          label: Text(_t('Camera')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isAnalyzing ? null : _pickFromGallery,
                          icon: const Icon(Icons.photo_library, size: 18),
                          label: Text(_t('Gallery')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.teal,
                            side: const BorderSide(color: Colors.teal),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Image preview
            if (_imageFile != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Image.file(_imageFile!, height: 200, width: double.infinity, fit: BoxFit.cover),
                    Positioned(
                      top: 8, right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() { _imageFile = null; _result = null; _urgencyLevel = null; }),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Description input
            if (_imageFile != null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: _t('Describe your symptoms (optional)'),
                  hintText: _t('e.g., It started 2 days ago, itchy, painful...'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.edit_note_rounded),
                ),
              ),
              const SizedBox(height: 12),
              // Analyze button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isAnalyzing ? null : _analyzeImage,
                  icon: _isAnalyzing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome_rounded),
                  label: Text(_isAnalyzing ? _t('Analyzing...') : _t('Analyze with AI')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],

            // Urgency badge
            if (_urgencyLevel != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _urgencyColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _urgencyColor().withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(_urgencyIcon(), color: _urgencyColor(), size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_t('Urgency Level'), style: TextStyle(fontWeight: FontWeight.bold, color: _urgencyColor())),
                          Text(_urgencyLevel!, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: _urgencyColor())),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Result
            if (_result != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1F2937) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.medical_services_rounded, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 8),
                        Text(_t('AI Assessment'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(_result!, style: const TextStyle(fontSize: 14, height: 1.5)),
                  ],
                ),
              ),
            ],

            // Empty state
            if (_imageFile == null && _result == null) ...[
              const SizedBox(height: 30),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Icon(Icons.health_and_safety_rounded, size: 48, color: Colors.teal.shade300),
                    const SizedBox(height: 12),
                    Text(_t('How it works'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _buildStep(Icons.camera_alt_rounded, _t('Take a photo of the affected area')),
                    _buildStep(Icons.description_rounded, _t('Describe your symptoms (optional)')),
                    _buildStep(Icons.auto_awesome_rounded, _t('Get AI-powered assessment')),
                    _buildStep(Icons.medical_services_rounded, _t('Receive first aid guidance')),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_t('For emergencies, call 108/112 immediately'),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.teal.shade600),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
