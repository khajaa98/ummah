// lib/screens/verification_queue_screen.dart
// =============================================================================
// VerificationQueueScreen — the core admin workflow page.
//
// Dual-pane layout for B2B admin verifiers:
//   - Left Pane: Displays the physical timetable photo uploaded by the admin.
//   - Right Pane: A Form with input fields populated by the Gemini OCR response.
//
// Reuses the model definitions for Mosque and PrayerTiming.
// Uses Riverpod for modular, testable state management.
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import '../models/mosque.dart';

// ---------------------------------------------------------------------------
// Base URL configuration (fallback to localhost:3000)
// ---------------------------------------------------------------------------
const String _apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000',
);

// ---------------------------------------------------------------------------
// State Providers
// ---------------------------------------------------------------------------

// Token state - stored in memory for testing
final adminTokenProvider = StateProvider<String>((ref) => '');

// List of mosques fetched from backend
final mosquesProvider = FutureProvider.autoDispose<List<Mosque>>((ref) async {
  final token = ref.watch(adminTokenProvider);
  if (token.isEmpty) return [];

  final response = await http.get(
    Uri.parse('$_apiBaseUrl/v1/mosques'),
    headers: {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    },
  );

  if (response.statusCode == 200) {
    final body = json.decode(response.body);
    final data = body['data'] as List;
    return data.map((m) => Mosque.fromJson(m as Map<String, dynamic>)).toList();
  } else {
    throw Exception('Failed to load mosques: ${response.statusCode}');
  }
});

// Currently selected mosque
final selectedMosqueProvider = StateProvider<Mosque?>((ref) => null);

// Picked file state
final pickedFileProvider = StateProvider<PlatformFile?>((ref) => null);

// Extracted timing response from OCR endpoint
final extractedTimingIdProvider = StateProvider<String?>((ref) => null);
final ocrLoadingProvider = StateProvider<bool>((ref) => false);
final verifyLoadingProvider = StateProvider<bool>((ref) => false);

// ---------------------------------------------------------------------------
// Verification Queue Screen Widget
// ---------------------------------------------------------------------------
class VerificationQueueScreen extends ConsumerStatefulWidget {
  const VerificationQueueScreen({super.key});

  @override
  ConsumerState<VerificationQueueScreen> createState() => _VerificationQueueScreenState();
}

class _VerificationQueueScreenState extends ConsumerState<VerificationQueueScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers for the form fields
  final _fajrController = TextEditingController();
  final _sunriseController = TextEditingController();
  final _dhuhrController = TextEditingController();
  final _asrController = TextEditingController();
  final _maghribController = TextEditingController();
  final _ishaController = TextEditingController();
  final _jumuahController = TextEditingController();

  @override
  void dispose() {
    _fajrController.dispose();
    _sunriseController.dispose();
    _dhuhrController.dispose();
    _asrController.dispose();
    _maghribController.dispose();
    _ishaController.dispose();
    _jumuahController.dispose();
    super.dispose();
  }

  // Populate controllers from the API response
  void _populateForm(Map<String, dynamic> data) {
    setState(() {
      _fajrController.text = data['fajr'] ?? '';
      _sunriseController.text = data['sunrise'] ?? '';
      _dhuhrController.text = data['dhuhr'] ?? '';
      _asrController.text = data['asr'] ?? '';
      _maghribController.text = data['maghrib'] ?? '';
      _ishaController.text = data['isha'] ?? '';
      _jumuahController.text = data['jumuah'] ?? data['jumu_ah'] ?? '';
    });
  }

  // Clear form controllers
  void _clearForm() {
    setState(() {
      _fajrController.clear();
      _sunriseController.clear();
      _dhuhrController.clear();
      _asrController.clear();
      _maghribController.clear();
      _ishaController.clear();
      _jumuahController.clear();
    });
    ref.read(extractedTimingIdProvider.notifier).state = null;
    ref.read(pickedFileProvider.notifier).state = null;
  }

  // Validate time format (HH:MM)
  String? _validateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    final regex = RegExp(r'^\d{2}:\d{2}$');
    if (!regex.hasMatch(value)) {
      return 'Must be HH:MM';
    }
    return null;
  }

  // Pick an image file using FilePicker
  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      withData: true, // Crucial for Flutter Web to get bytes
    );

    if (result != null && result.files.isNotEmpty) {
      ref.read(pickedFileProvider.notifier).state = result.files.first;
      // Reset extracted state if a new file is picked
      ref.read(extractedTimingIdProvider.notifier).state = null;
    }
  }

  // Upload image to backend OCR endpoint
  Future<void> _processWithGemini() async {
    final mosque = ref.read(selectedMosqueProvider);
    final file = ref.read(pickedFileProvider);
    final token = ref.read(adminTokenProvider);

    if (mosque == null || file == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a mosque, pick an image, and provide a valid token.')),
      );
      return;
    }

    ref.read(ocrLoadingProvider.notifier).state = true;

    try {
      final uri = Uri.parse('$_apiBaseUrl/v1/mosques/${mosque.id}/timings/upload');
      final request = http.MultipartRequest('POST', uri);
      
      request.headers['Authorization'] = 'Bearer $token';
      
      // Attach the file bytes (works perfectly on Flutter Web)
      final multipartFile = http.MultipartFile.fromBytes(
        'timetable',
        file.bytes!,
        filename: file.name,
      );
      request.files.add(multipartFile);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        final body = json.decode(response.body);
        final timingData = body['data'];
        
        ref.read(extractedTimingIdProvider.notifier).state = timingData['id'];
        _populateForm(timingData);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Timetable processed successfully! Verify and edit details on the right pane.'),
            backgroundColor: Colors.teal,
          ),
        );
      } else {
        final body = json.decode(response.body);
        final errorMsg = body['error']?['message'] ?? 'Status: ${response.statusCode}';
        throw Exception(errorMsg);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('OCR Failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      ref.read(ocrLoadingProvider.notifier).state = false;
    }
  }

  // Publish verified timings to backend
  Future<void> _verifyAndPublish() async {
    if (!_formKey.currentState!.validate()) return;

    final mosque = ref.read(selectedMosqueProvider);
    final timingId = ref.read(extractedTimingIdProvider);
    final token = ref.read(adminTokenProvider);

    if (mosque == null || timingId == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing reference information.')),
      );
      return;
    }

    ref.read(verifyLoadingProvider.notifier).state = true;

    try {
      final uri = Uri.parse('$_apiBaseUrl/v1/mosques/${mosque.id}/timings/$timingId/verify');
      final payload = {
        'fajr': _fajrController.text,
        'sunrise': _sunriseController.text,
        'dhuhr': _dhuhrController.text,
        'asr': _asrController.text,
        'maghrib': _maghribController.text,
        'isha': _ishaController.text,
        'jumuah': _jumuahController.text.isNotEmpty ? _jumuahController.text : null,
      };

      final response = await http.put(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Prayer timings published to Postgres database!'),
            backgroundColor: Colors.green,
          ),
        );
        _clearForm();
      } else {
        final body = json.decode(response.body);
        final errorMsg = body['error']?['message'] ?? 'Status: ${response.statusCode}';
        throw Exception(errorMsg);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Publish Failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      ref.read(verifyLoadingProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final token = ref.watch(adminTokenProvider);
    final mosquesAsync = ref.watch(mosquesProvider);
    final selectedMosque = ref.watch(selectedMosqueProvider);
    final pickedFile = ref.watch(pickedFileProvider);
    final extractedTimingId = ref.watch(extractedTimingIdProvider);
    final ocrLoading = ref.watch(ocrLoadingProvider);
    final verifyLoading = ref.watch(verifyLoadingProvider);

    final scheme = Theme.of(context).colorScheme;
    final isWideScreen = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Row(
          children: [
            Icon(Icons.admin_panel_settings_rounded, color: scheme.primary, size: 28),
            const SizedBox(width: 10),
            Text(
              'Ummah Verification Dashboard',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Card(
              color: scheme.secondaryContainer,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'B2B Operations',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Token Input Box
          Container(
            width: 250,
            padding: const EdgeInsets.symmetric(vertical: 8),
            margin: const EdgeInsets.only(right: 16),
            child: TextField(
              obscureText: true,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Enter Admin JWT Token',
                prefixIcon: const Icon(Icons.vpn_key_rounded, size: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              ),
              onChanged: (val) {
                ref.read(adminTokenProvider.notifier).state = val;
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Warning banner if token is empty ─────────────────────────────────
          if (token.isEmpty)
            Container(
              color: scheme.errorContainer,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Authorization token is missing. Please generate a token using generateToken.js and paste it in the top-right field to fetch mosques and perform verification.',
                      style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // ── Mosque Selection and File Picking Bar ──────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              color: scheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: scheme.outlineVariant, width: 0.8),
              ),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Mosque Selector Dropdown
                    Expanded(
                      flex: 2,
                      child: mosquesAsync.when(
                        data: (list) {
                          if (list.isEmpty) {
                            return const Text('Paste admin token to load mosques');
                          }
                          return DropdownButtonFormField<Mosque>(
                            initialValue: selectedMosque,
                            hint: const Text('Select Mosque to Upload'),
                            decoration: InputDecoration(
                              labelText: 'Mosque',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            items: list.map((m) {
                              return DropdownMenuItem(
                                value: m,
                                child: Text('${m.name} (${m.city})'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              ref.read(selectedMosqueProvider.notifier).state = val;
                            },
                          );
                        },
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, _) => Text('Error loading mosques: $err', style: TextStyle(color: scheme.error)),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // File Picker Button
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: _pickImage,
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(
                            border: Border.all(color: scheme.outline),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Icon(Icons.image_outlined, color: scheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  pickedFile != null ? pickedFile.name : 'Select Timetable Image',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Process Button
                    ElevatedButton.icon(
                      onPressed: (ocrLoading || selectedMosque == null || pickedFile == null)
                          ? null
                          : _processWithGemini,
                      icon: ocrLoading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome_rounded),
                      label: const Text('OCR Extract (Gemini)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: scheme.primaryContainer,
                        foregroundColor: scheme.onPrimaryContainer,
                        minimumSize: const Size(200, 56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Main dual-pane view ───────────────────────────────────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left Pane: Timetable image preview ───────────────────────────
                Expanded(
                  flex: 1,
                  child: Container(
                    margin: const EdgeInsets.only(left: 16, bottom: 16, right: 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: scheme.outlineVariant, width: 0.8),
                    ),
                    child: pickedFile != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: InteractiveViewer(
                              maxScale: 4.0,
                              child: Image.memory(
                                pickedFile.bytes!,
                                fit: BoxFit.contain,
                              ),
                            ),
                          )
                        : Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined, size: 64, color: scheme.outline),
                                const SizedBox(height: 12),
                                Text(
                                  'Select a timetable image above to display preview.',
                                  style: TextStyle(color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),

                // ── Right Pane: Editable Timetable Form ──────────────────────────
                Expanded(
                  flex: 1,
                  child: Container(
                    margin: const EdgeInsets.only(right: 16, bottom: 16, left: 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: scheme.outlineVariant, width: 0.8),
                    ),
                    child: extractedTimingId != null
                        ? Form(
                            key: _formKey,
                            child: ListView(
                              padding: const EdgeInsets.all(24),
                              children: [
                                Text(
                                  'OCR Results Editor',
                                  style: GoogleFonts.outfit(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Review and adjust the extracted times if Gemini made errors. Click Verify & Publish to save to production.',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                                const Divider(height: 32),

                                // Grid of timings
                                GridView.count(
                                  crossAxisCount: 2,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  childAspectRatio: 2.8,
                                  children: [
                                    _buildTimeField('Fajr', _fajrController),
                                    _buildTimeField('Sunrise', _sunriseController),
                                    _buildTimeField('Dhuhr', _dhuhrController),
                                    _buildTimeField('Asr', _asrController),
                                    _buildTimeField('Maghrib', _maghribController),
                                    _buildTimeField('Isha', _ishaController),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _buildTimeField("Jumu'ah (Friday Congregation) - Optional", _jumuahController, isRequired: false),

                                const SizedBox(height: 32),

                                // Verify & Publish Button
                                ElevatedButton.icon(
                                  onPressed: verifyLoading ? null : _verifyAndPublish,
                                  icon: verifyLoading
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.verified_user_rounded),
                                  label: Text(
                                    'Verify and Publish Timetable',
                                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: scheme.primary,
                                    foregroundColor: scheme.onPrimary,
                                    minimumSize: const Size(double.infinity, 56),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    elevation: 0,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: _clearForm,
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 44),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Cancel / Reset'),
                                ),
                              ],
                            ),
                          )
                        : Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit_note_rounded, size: 64, color: scheme.outline),
                                const SizedBox(height: 12),
                                Text(
                                  ocrLoading
                                      ? 'AI is analyzing your timetable photo...'
                                      : 'Timetable data will populate here after OCR extraction.',
                                  style: TextStyle(color: scheme.onSurfaceVariant),
                                ),
                                if (ocrLoading) ...[
                                  const SizedBox(height: 16),
                                  const SizedBox(width: 200, child: LinearProgressIndicator()),
                                ],
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeField(String label, TextEditingController controller, {bool isRequired = true}) {
    final scheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'HH:MM',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        prefixIcon: const Icon(Icons.access_time_rounded, size: 18),
      ),
      keyboardType: TextInputType.datetime,
      validator: isRequired ? _validateTime : (val) {
        if (val != null && val.trim().isNotEmpty) {
          return _validateTime(val);
        }
        return null;
      },
    );
  }
}
