/// Profile Screen — User demographic settings
///
/// Collects Age, Height, and Weight — required inputs for the
/// paper's Algorithm 3 (Chandrasekaran blood pressure model).
/// Without these, only heart rate (Algorithm 2) can be computed.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/app_database.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'User');
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loadProfile();
      _loaded = true;
    }
  }

  Future<void> _loadProfile() async {
    final db = Provider.of<AppDatabase>(context, listen: false);
    final profile = await db.getUserProfile();
    if (profile != null) {
      _nameController.text = profile.name;
      _ageController.text = profile.age.toString();
      _heightController.text = profile.heightCm.toStringAsFixed(0);
      _weightController.text = profile.weightKg.toStringAsFixed(0);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                // Header
                const Text(
                  'Profile',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Required for blood pressure estimation (Algorithm 3)',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 28),

                // Algorithm 3 explanation card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.accentCyan.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.accentCyan.withOpacity(0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          color: AppColors.accentCyan, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Why do we need this?',
                              style: TextStyle(
                                color: AppColors.accentCyan,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'The Chandrasekaran hemodynamic model uses your age, '
                              'height, and weight to estimate Body Surface Area (BSA), '
                              'Stroke Volume (SV), and ultimately Blood Pressure.\n\n'
                              'Without these values, the app can only measure Heart Rate.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Name
                _buildField(
                  controller: _nameController,
                  label: 'Name',
                  icon: Icons.person_outline,
                  hint: 'Your name',
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 16),

                // Age
                _buildField(
                  controller: _ageController,
                  label: 'Age',
                  icon: Icons.cake_outlined,
                  hint: 'e.g. 21',
                  suffix: 'years',
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final n = int.tryParse(v);
                    if (n == null || n < 5 || n > 120) {
                      return 'Enter a valid age (5–120)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Height
                _buildField(
                  controller: _heightController,
                  label: 'Height',
                  icon: Icons.height,
                  hint: 'e.g. 170',
                  suffix: 'cm',
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final n = double.tryParse(v);
                    if (n == null || n < 50 || n > 250) {
                      return 'Enter a valid height (50–250 cm)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Weight
                _buildField(
                  controller: _weightController,
                  label: 'Weight',
                  icon: Icons.monitor_weight_outlined,
                  hint: 'e.g. 65',
                  suffix: 'kg',
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final n = double.tryParse(v);
                    if (n == null || n < 10 || n > 300) {
                      return 'Enter a valid weight (10–300 kg)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saveProfile,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Profile'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Formulas reference
                _buildFormulasCard(),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    String? suffix,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.textTertiary, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            suffixText: suffix,
            suffixStyle: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormulasCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.functions, color: AppColors.accentPurple, size: 18),
              const SizedBox(width: 8),
              const Text(
                'How your data is used',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _formulaLine('BSA', '0.007184 × W^0.425 × H^0.725'),
          _formulaLine('SV', '−6.6 + 0.25(ET−35) − 0.62×HR + 40.4×BSA − 0.51×Age'),
          _formulaLine('PP', 'SV / (0.013W − 0.007Age − 0.004HR + 1.307)'),
          const SizedBox(height: 8),
          Text(
            'Source: Sharma et al. (2022), Algorithm 3',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _formulaLine(String name, String formula) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              name,
              style: const TextStyle(
                color: AppColors.accentCyan,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Text(' = ',
              style:
                  TextStyle(color: AppColors.textTertiary, fontSize: 12)),
          Expanded(
            child: Text(
              formula,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final db = Provider.of<AppDatabase>(context, listen: false);
    await db.saveUserProfile(
      name: _nameController.text,
      age: int.parse(_ageController.text),
      heightCm: double.parse(_heightController.text),
      weightKg: double.parse(_weightController.text),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile saved!'),
          backgroundColor: AppColors.accentGreen,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }
}
