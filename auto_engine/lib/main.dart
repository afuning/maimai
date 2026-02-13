import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auto Engine',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Weibo Scraper Console'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const platform = MethodChannel(
    'com.example.auto_engine/accessibility',
  );

  String _accessibilityStatus = 'Unknown';
  bool _isTaskActive = false;
  String _lastScrapedValue = 'N/A';
  String _lastScrapeTime = 'Never';

  final TextEditingController _containerIdController = TextEditingController(
    text: "10080844cc042c1e6385c391f94e8094939df5",
  ); // Example or placeholder

  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _checkAccessibility();
    _startStatusMonitoring();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _containerIdController.dispose();
    super.dispose();
  }

  void _startStatusMonitoring() {
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _updateTaskStatus();
    });
  }

  Future<void> _updateTaskStatus() async {
    try {
      final Map<dynamic, dynamic>? status = await platform.invokeMethod(
        'getTaskStatus',
      );
      if (status != null) {
        setState(() {
          _isTaskActive = status['isActive'] ?? false;
          final int timeMs = status['lastScrapeTime'] ?? 0;
          if (timeMs > 0) {
            _lastScrapeTime = DateTime.fromMillisecondsSinceEpoch(
              timeMs,
            ).toString().split('.').first;
          }
          _lastScrapedValue = status['lastScrapeValue'] ?? 'N/A';
        });
      }
    } catch (e) {
      debugPrint("Error updating status: $e");
    }
  }

  Future<void> _checkAccessibility() async {
    try {
      final bool result = await platform.invokeMethod('isAccessibilityEnabled');
      setState(() {
        _accessibilityStatus = result ? 'Enabled' : 'Disabled';
      });
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Future<void> _toggleTask() async {
    try {
      if (_isTaskActive) {
        await platform.invokeMethod('stopTask');
      } else {
        await platform.invokeMethod('startTask', {
          'containerId': _containerIdController.text.trim(),
        });
      }
      _updateTaskStatus();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _testScrape() async {
    try {
      await platform.invokeMethod('testScrape', {
        'containerId': _containerIdController.text.trim(),
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Test scrape triggered...")));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Test Error: $e")));
    }
  }

  Future<void> _openAccessibilitySettings() async {
    await platform.invokeMethod('openAccessibilitySettings');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 20),
            _buildControlCard(),
            const SizedBox(height: 20),
            _buildLogCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Accessibility Service:',
                  style: TextStyle(fontSize: 16),
                ),
                GestureDetector(
                  onTap: _openAccessibilitySettings,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _accessibilityStatus == 'Enabled'
                          ? Colors.green
                          : Colors.red,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _accessibilityStatus,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Task Runner Status:',
                  style: TextStyle(fontSize: 16),
                ),
                Text(
                  _isTaskActive ? 'RUNNING' : 'STOPPED',
                  style: TextStyle(
                    color: _isTaskActive ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Configuration',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _containerIdController,
              decoration: const InputDecoration(
                labelText: 'Weibo Container ID',
                border: OutlineInputBorder(),
                hintText: 'Enter containerId here',
              ),
              enabled: !_isTaskActive,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _toggleTask,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isTaskActive ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                ),
                icon: Icon(_isTaskActive ? Icons.stop : Icons.play_arrow),
                label: Text(
                  _isTaskActive ? 'STOP DAILY TASK' : 'START DAILY TASK',
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: OutlinedButton.icon(
                onPressed: _testScrape,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                icon: const Icon(Icons.bug_report),
                label: const Text('TEST SCRAPE NOW'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard() {
    return Card(
      elevation: 4,
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Last Scrape Info',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            _buildLogRow('Value:', _lastScrapedValue, Colors.amber),
            _buildLogRow('Time:', _lastScrapeTime, Colors.white),
            const SizedBox(height: 10),
            const Text(
              'Next scrape will be triggered automatically in ~30m.',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(width: 10),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
