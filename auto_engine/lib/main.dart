import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'trend_analysis_page.dart';

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

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  static const platform = MethodChannel(
    'com.example.auto_engine/accessibility',
  );

  String _accessibilityStatus = 'Unknown';
  bool _isTaskActive = false;
  String _lastScrapedValue = 'N/A';
  String _lastScrapeTime = 'Never';
  String _lastError = '';

  final TextEditingController _containerIdController = TextEditingController(
    text: "10080844cc042c1e6385c391f94e8094939df5",
  );

  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccessibility();
    _startStatusMonitoring();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    _containerIdController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccessibility();
    }
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
          _lastError = status['lastError'] ?? '';
          _lastScrapedValue = status['lastScrapeValue'] ?? 'N/A';
          final int timeMs = status['lastScrapeTime'] ?? 0;
          if (timeMs > 0) {
            _lastScrapeTime = DateTime.fromMillisecondsSinceEpoch(
              timeMs,
            ).toString().split('.').first;
          }
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _testScrape() async {
    try {
      await platform.invokeMethod('testScrape', {
        'containerId': _containerIdController.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Test scrape triggered...")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Test Error: $e")));
      }
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
            const SizedBox(height: 20),
            _buildAnalysisLauncher(),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisLauncher() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TrendAnalysisPage()),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.analytics,
                  color: Colors.indigo,
                  size: 30,
                ),
              ),
              const SizedBox(width: 20),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trend Analysis',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'View and compare growth curves',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
            ],
          ),
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
                Expanded(
                  child: Row(
                    children: [
                      const Flexible(
                        child: Text(
                          'Accessibility Service:',
                          style: TextStyle(fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(
                          Icons.refresh,
                          size: 20,
                          color: Colors.grey,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: _checkAccessibility,
                        tooltip: "Refresh Status",
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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
            if (_lastError.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(color: Colors.grey),
              const Text(
                'Status/Error:',
                style: TextStyle(color: Colors.redAccent, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                _lastError,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ],
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
