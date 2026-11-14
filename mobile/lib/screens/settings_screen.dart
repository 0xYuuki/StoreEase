import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  bool _isLoading = true;
  bool _isTesting = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final storage = context.read<StorageService>();
    final url = await storage.getServerUrl();
    final token = await storage.getAuthToken();
    setState(() {
      _urlController.text = url;
      _tokenController.text = token ?? '';
      _isLoading = false;
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final storage = context.read<StorageService>();
    final api = context.read<ApiService>();
    await storage.setServerUrl(_urlController.text.trim());
    await storage.setAuthToken(_tokenController.text.trim());

    try {
      final role = await api.testConnection();
      if (!mounted) return;
      setState(() {
        _isTesting = false;
        _testSuccess = true;
        _testResult = 'Connected successfully! (Role: $role)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTesting = false;
        _testSuccess = false;
        _testResult = 'Connection failed: $e';
      });
    }
  }

  Future<void> _saveSettings() async {
    final storage = context.read<StorageService>();
    await storage.setServerUrl(_urlController.text.trim());
    await storage.setAuthToken(_tokenController.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Connection'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 8),
            Image.asset(
              'assets/logo.png',
              height: 70,
              errorBuilder: (_, _, _) => const Icon(Icons.store, size: 64, color: AppTheme.primaryGreen),
            ),
            const SizedBox(height: 8),
            const Text(
              "Helen's Store Mobile POS",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Version 1.0.0 (Native Flutter)',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 24),

            // Server Config Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.dns_outlined, color: AppTheme.primaryGreen, size: 20),
                        SizedBox(width: 8),
                        Text('Backend Server Connection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: 'Server Base URL',
                        hintText: 'http://192.168.1.X:3000',
                        prefixIcon: Icon(Icons.link),
                        helperText: 'For Android emulator use http://10.0.2.2:3000',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _tokenController,
                      decoration: const InputDecoration(
                        labelText: 'Access Token (Optional)',
                        hintText: 'Leave empty for trusted localhost mode',
                        prefixIcon: Icon(Icons.key),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: _isTesting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.wifi_find, size: 18),
                            label: const Text('Test Connection'),
                            onPressed: _isTesting ? null : _testConnection,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.save, size: 18),
                            label: const Text('Save Settings'),
                            onPressed: _saveSettings,
                          ),
                        ),
                      ],
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _testSuccess ? AppTheme.primaryLight : AppTheme.dangerLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _testSuccess ? AppTheme.primaryGreen : AppTheme.dangerRed,
                          ),
                        ),
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _testSuccess ? AppTheme.primaryDark : AppTheme.dangerRed,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
