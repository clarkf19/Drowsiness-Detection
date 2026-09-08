import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/alert_service.dart';
import '../services/settings_service.dart';

/// Screen allowing the driver to adjust alarm volume, vibration, sensitivity,
/// and emergency contact information.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingButtonController _phoneController;
  final AlertService _previewAlertService = AlertService();

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _phoneController = TextEditingButtonController(text: settings.emergencyContact);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _previewAlertService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Deep cockpit slate
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: const Text(
          'Settings & Safety',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: [
          // Section: Alert & Audio
          _buildSectionHeader('ALARM & NOTIFICATION', Icons.volume_up_rounded),
          const SizedBox(height: 12),
          _buildCard(
            children: [
              // Alarm Volume
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Alarm Volume',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${(settings.alarmVolume * 100).toInt()}%',
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFF38BDF8),
                  inactiveTrackColor: Colors.white12,
                  thumbColor: const Color(0xFF38BDF8),
                  overlayColor: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: settings.alarmVolume,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  onChanged: (val) => settings.setAlarmVolume(val),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _previewAlertService.playTestSound(settings.alarmVolume),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18, color: Color(0xFF38BDF8)),
                  label: const Text('Test Alarm Sound', style: TextStyle(color: Color(0xFF38BDF8))),
                ),
              ),

              const Divider(color: Colors.white10, height: 24),

              // Vibration Toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Haptic Vibration',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Pulse vibration motor during drowsy alerts',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                activeThumbColor: const Color(0xFF10B981),
                value: settings.vibrationEnabled,
                onChanged: (val) => settings.setVibrationEnabled(val),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Section: Model Sensitivity
          _buildSectionHeader('DETECTION SENSITIVITY', Icons.tune_rounded),
          const SizedBox(height: 12),
          _buildCard(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Smoothing Window Size',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${settings.smoothingWindow} Frames',
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                settings.smoothingWindow <= 2
                    ? 'Fastest alert trigger (high sensitivity)'
                    : settings.smoothingWindow == 3
                        ? 'Balanced sensitivity (recommended)'
                        : 'Maximum blink & movement filtering',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFF38BDF8),
                  inactiveTrackColor: Colors.white12,
                  thumbColor: const Color(0xFF38BDF8),
                  overlayColor: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: settings.smoothingWindow.toDouble(),
                  min: 2,
                  max: 5,
                  divisions: 3,
                  label: '${settings.smoothingWindow} frames',
                  onChanged: (val) => settings.setSmoothingWindow(val.toInt()),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Section: Emergency SOS Contact
          _buildSectionHeader('EMERGENCY SOS', Icons.contact_emergency_rounded),
          const SizedBox(height: 12),
          _buildCard(
            children: [
              const Text(
                'Auto-Notify Contact',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Recipient notified if a Drowsy alert remains un-dismissed for >15 seconds',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '+1 555-0199 or emergency contact number',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  prefixIcon: const Icon(Icons.phone_rounded, color: Color(0xFF38BDF8), size: 18),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
                    onPressed: () {
                      settings.setEmergencyContact(_phoneController.text);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Emergency contact saved')),
                      );
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                  ),
                ),
                onSubmitted: (val) => settings.setEmergencyContact(val),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Section: System Info Card
          _buildSectionHeader('AI ENGINE & MODEL', Icons.memory_rounded),
          const SizedBox(height: 12),
          _buildCard(
            children: [
              _buildInfoRow('Feature Extractor', 'EfficientNet-B0 (512-dim)'),
              const Divider(color: Colors.white10, height: 16),
              _buildInfoRow('Sequence Model', '2-Layer LSTM (30-frame window)'),
              const Divider(color: Colors.white10, height: 16),
              _buildInfoRow('Safety Policy', 'Unified Drowsy / High Sensitivity'),
              const Divider(color: Colors.white10, height: 16),
              _buildInfoRow('Face Detection', 'Google ML Kit Fast Mode'),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF38BDF8)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Helper controller
class TextEditingButtonController extends TextEditingController {
  TextEditingButtonController({super.text});
}
