import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class TrendAnalysisPage extends StatefulWidget {
  const TrendAnalysisPage({super.key});

  @override
  State<TrendAnalysisPage> createState() => _TrendAnalysisPageState();
}

class _TrendAnalysisPageState extends State<TrendAnalysisPage> {
  static const platform = MethodChannel(
    'com.example.auto_engine/accessibility',
  );

  Map<String, List<TrendData>> _groupedHistory = {};
  String? _selectedDate;
  String? _compareDate;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final String? csvData = await platform.invokeMethod('getHistory');
      if (!mounted) return;

      if (csvData != null && csvData.isNotEmpty) {
        final List<TrendData> parsed = _parseCsv(csvData);
        final Map<String, List<TrendData>> grouped = {};

        for (var data in parsed) {
          final dateKey =
              "${data.time.year}-${data.time.month.toString().padLeft(2, '0')}-${data.time.day.toString().padLeft(2, '0')}";
          grouped.putIfAbsent(dateKey, () => []).add(data);
        }

        setState(() {
          _groupedHistory = grouped;
          final dates = grouped.keys.toList()..sort();
          if (dates.isNotEmpty) {
            _selectedDate ??= dates.last;
            if (_selectedDate != null && !grouped.containsKey(_selectedDate!)) {
              _selectedDate = dates.last;
            }
            if (_compareDate == null && dates.length > 1) {
              _compareDate = dates[dates.length - 2];
            }
          }
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<TrendData> _parseCsv(String csv) {
    final List<TrendData> list = [];
    final lines = csv.split('\n');
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final parts = line.split(',');
      if (parts.length < 3) continue;

      final valueStr = parts.sublist(2).join(",");
      final value = _parseValue(valueStr);
      if (value == null) continue;

      try {
        list.add(TrendData(DateTime.parse(parts[0]), value));
      } catch (e) {
        debugPrint("TrendPage: Date parse error at line $i");
      }
    }
    return list;
  }

  double? _parseValue(String input) {
    String clean = input.trim().replaceAll(',', '');
    double multiplier = 1.0;
    if (clean.contains('万')) {
      multiplier = 10000.0;
      clean = clean.replaceAll('万', '');
    }
    clean = clean.replaceAll(RegExp(r'[^0-9.]'), '');
    final val = double.tryParse(clean);
    return val != null ? val * multiplier : null;
  }

  Future<void> _showRawData(BuildContext context) async {
    try {
      final String? csvData = await platform.invokeMethod('getHistory');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Raw CSV Data"),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: SelectableText(csvData ?? "Empty"),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint("Error dumping CSV: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final dates = _groupedHistory.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trend Analysis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: "Raw Data",
            onPressed: () => _showRawData(context),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: "Export Report",
            onPressed: _exportReport,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchHistory),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groupedHistory.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_toggle_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "No records found yet.",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildComparisonSelectors(dates),
                  const SizedBox(height: 25),
                  _buildChartContainer(),
                  const SizedBox(height: 20),
                  _buildLegend(),
                  const SizedBox(height: 30),
                  const Text(
                    'Recent Stats',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  _buildStatsList(),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _showRecordsManagement,
                        icon: const Icon(Icons.edit_note, size: 20),
                        label: const Text("Manage Records"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildComparisonSelectors(List<String> dates) {
    return Row(
      children: [
        Expanded(
          child: _buildDropDown(
            label: "Target Date",
            value: _selectedDate,
            items: dates,
            onChanged: (v) => setState(() => _selectedDate = v),
            color: Colors.indigo,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: _buildDropDown(
            label: "Compare With",
            value: _compareDate,
            items: [null, ...dates],
            onChanged: (v) => setState(() => _compareDate = v),
            color: Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildChartContainer() {
    return Container(
      height: 250,
      width: double.infinity,
      padding: const EdgeInsets.only(left: 40, right: 10, bottom: 25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TrendChart(
        primaryData: _groupedHistory[_selectedDate] ?? [],
        compareData: _compareDate != null
            ? (_groupedHistory[_compareDate] ?? [])
            : null,
      ),
    );
  }

  Widget _buildDropDown({
    required String label,
    required String? value,
    required List<String?> items,
    required ValueChanged<String?> onChanged,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        DropdownButton<String?>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: color),
          underline: Container(height: 2, color: color.withOpacity(0.5)),
          items: items.map((date) {
            return DropdownMenuItem<String?>(
              value: date,
              child: Text(
                date ?? "Disabled",
                style: TextStyle(
                  fontSize: 14,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendItem(_selectedDate ?? "Target", Colors.indigo),
        if (_compareDate != null) ...[
          const SizedBox(width: 30),
          _legendItem(_compareDate!, Colors.orange),
        ],
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildStatsList() {
    final targetData = _groupedHistory[_selectedDate] ?? [];
    if (targetData.isEmpty) return const SizedBox.shrink();

    final lastVal = targetData.last.value;
    final firstVal = targetData.first.value;
    final growth = lastVal - firstVal;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStatRow("Today's Start", _formatValue(firstVal)),
            const Divider(),
            _buildStatRow("Current Value", _formatValue(lastVal)),
            const Divider(),
            _buildStatRow(
              "Growth Today",
              "+${_formatValue(growth)}",
              valueColor: Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  String _formatValue(double val) {
    if (val >= 10000) return "${(val / 10000).toStringAsFixed(1)}万";
    return val.toInt().toString();
  }

  Future<void> _exportReport() async {
    if (_isLoading || _selectedDate == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final targetData = _groupedHistory[_selectedDate] ?? [];
      final compareData = _compareDate != null
          ? (_groupedHistory[_compareDate] ?? [])
          : null;

      final reportWidget = Material(
        color: Colors.white,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Zhao Jinmai Super-Like Report",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Target Date: $_selectedDate",
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              if (_compareDate != null)
                Text(
                  "Comparison Date: $_compareDate",
                  style: const TextStyle(fontSize: 14, color: Colors.orange),
                ),
              const SizedBox(height: 24),
              const Text(
                "Trend Comparison Chart",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                height: 200,
                padding: const EdgeInsets.only(
                  left: 35,
                  right: 10,
                  bottom: 20,
                  top: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TrendChart(
                  primaryData: targetData,
                  compareData: compareData,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                "Detailed Records (Today)",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Table(
                border: TableBorder.all(
                  color: Colors.grey.shade300,
                  width: 0.5,
                ),
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(1.5),
                  2: FlexColumnWidth(1),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: Colors.grey.shade100),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          "Time",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          "Value",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          "Growth",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ...List.generate(targetData.length, (index) {
                    final record = targetData[index];
                    final prev = index > 0
                        ? targetData[index - 1].value
                        : record.value;
                    final diff = record.value - prev;
                    final timeStr =
                        "${record.time.hour.toString().padLeft(2, '0')}:${record.time.minute.toString().padLeft(2, '0')}";
                    return TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            timeStr,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            _formatValue(record.value),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            index == 0 ? "-" : "+${_formatValue(diff)}",
                            style: TextStyle(
                              color: diff > 0 ? Colors.green : Colors.grey,
                              fontWeight: diff > 0
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              const SizedBox(height: 32),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  "Exported from Auto Engine",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      final boundary = RenderRepaintBoundary();
      final view = ui.PlatformDispatcher.instance.views.first;
      final pipelineOwner = PipelineOwner();
      final buildOwner = BuildOwner(focusManager: FocusManager());

      final renderView = RenderView(
        view: view,
        configuration: ViewConfiguration(
          logicalConstraints: BoxConstraints.tight(const ui.Size(400, 2000)),
          devicePixelRatio: view.devicePixelRatio,
        ),
        child: RenderPositionedBox(
          alignment: Alignment.topLeft,
          child: boundary,
        ),
      );

      pipelineOwner.rootNode = renderView;
      renderView.prepareInitialFrame();

      final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
        container: boundary,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: reportWidget,
        ),
      ).attachToRenderTree(buildOwner);

      buildOwner.buildScope(rootElement);
      buildOwner.finalizeTree();

      pipelineOwner.flushLayout();
      pipelineOwner.flushCompositingBits();
      pipelineOwner.flushPaint();

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/trend_report_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(pngBytes);

      if (mounted) Navigator.pop(context);

      await Share.shareXFiles([
        XFile(file.path),
      ], text: '赵今麦超话趋势报告 - $_selectedDate');
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Export Error: $e")));
      }
      debugPrint("Export failed: $e");
    }
  }

  void _showRecordsManagement() {
    final selectedRecords = _groupedHistory[_selectedDate] ?? [];
    if (selectedRecords.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Records for $_selectedDate",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 20),
                itemCount: selectedRecords.length,
                itemBuilder: (context, index) {
                  final record = selectedRecords[index];
                  final timeStr =
                      "${record.time.hour.toString().padLeft(2, '0')}:${record.time.minute.toString().padLeft(2, '0')}:${record.time.second.toString().padLeft(2, '0')}";

                  return ListTile(
                    leading: const Icon(Icons.history, color: Colors.indigo),
                    title: Text(
                      _formatValue(record.value),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(timeStr),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.edit,
                            size: 18,
                            color: Colors.grey,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _editRecord(record);
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Colors.redAccent,
                          ),
                          onPressed: () => _confirmDelete(record),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(TrendData record) {
    final timestamp =
        "${record.time.year}-${record.time.month.toString().padLeft(2, '0')}-${record.time.day.toString().padLeft(2, '0')} "
        "${record.time.hour.toString().padLeft(2, '0')}:${record.time.minute.toString().padLeft(2, '0')}:${record.time.second.toString().padLeft(2, '0')}";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Record?"),
        content: Text(
          "Are you sure you want to delete the record from $timestamp?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final success = await platform.invokeMethod('deleteRecord', {
                'timestamp': timestamp,
              });

              if (mounted) {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Close bottom sheet
                if (success == true) {
                  _fetchHistory();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Record deleted successfully"),
                    ),
                  );
                }
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _editRecord(TrendData record) {
    final controller = TextEditingController(
      text: record.value.toInt().toString(),
    );
    final timestamp =
        "${record.time.year}-${record.time.month.toString().padLeft(2, '0')}-${record.time.day.toString().padLeft(2, '0')} "
        "${record.time.hour.toString().padLeft(2, '0')}:${record.time.minute.toString().padLeft(2, '0')}:${record.time.second.toString().padLeft(2, '0')}";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Record"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Time: $timestamp",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "New Value",
                border: OutlineInputBorder(),
                suffixText: "人",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newVal = controller.text.trim();
              if (newVal.isNotEmpty) {
                final success = await platform.invokeMethod('updateRecord', {
                  'timestamp': timestamp,
                  'newValue': "${newVal}人",
                });

                if (mounted) {
                  Navigator.pop(context);
                  if (success == true) {
                    _fetchHistory();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Record updated successfully"),
                      ),
                    );
                  }
                }
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }
}

class TrendData {
  final DateTime time;
  final double value;
  TrendData(this.time, this.value);
}

class TrendChart extends StatefulWidget {
  final List<TrendData> primaryData;
  final List<TrendData>? compareData;

  const TrendChart({super.key, required this.primaryData, this.compareData});

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart> {
  TrendData? _selectedPoint;

  @override
  void didUpdateWidget(TrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryData != widget.primaryData) {
      _selectedPoint = null;
    }
  }

  (double, double) _getTimeRange() {
    if (widget.primaryData.isEmpty) return (0.0, 1440.0);

    double min =
        widget.primaryData.first.time.hour * 60.0 +
        widget.primaryData.first.time.minute;
    double max =
        widget.primaryData.last.time.hour * 60.0 +
        widget.primaryData.last.time.minute;

    if (widget.compareData != null && widget.compareData!.isNotEmpty) {
      final cMin =
          widget.compareData!.first.time.hour * 60.0 +
          widget.compareData!.first.time.minute;
      final cMax =
          widget.compareData!.last.time.hour * 60.0 +
          widget.compareData!.last.time.minute;
      if (cMin < min) min = cMin;
      if (cMax > max) max = cMax;
    }

    // Ensure a minimum range of 2 hours and align to hour boundaries
    min = (min / 60).floor() * 60.0;
    max = (max / 60).ceil() * 60.0;

    if (max - min < 120) {
      max = min + 120;
    }
    // Cap at 24h
    if (max > 1440) max = 1440;

    return (min, max);
  }

  void _handleTap(TapDownDetails details) {
    if (widget.primaryData.isEmpty) return;

    final RenderBox box = context.findRenderObject() as RenderBox;
    final Size size = box.size;
    final Offset localPos = details.localPosition;

    final (minMinutes, maxMinutes) = _getTimeRange();
    final range = maxMinutes - minMinutes;

    TrendData? closest;
    double minDistance = double.infinity;

    for (var data in widget.primaryData) {
      final minutes = data.time.hour * 60.0 + data.time.minute;
      final x = (minutes - minMinutes) / range * size.width;
      final distance = (x - localPos.dx).abs();
      if (distance < minDistance) {
        minDistance = distance;
        closest = data;
      }
    }

    if (minDistance < 30) {
      setState(() {
        _selectedPoint = closest;
      });
    } else {
      setState(() {
        _selectedPoint = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: _ChartPainter(
              widget.primaryData,
              widget.compareData,
              _selectedPoint,
            ),
          ),
          if (_selectedPoint != null) _buildTooltip(),
        ],
      ),
    );
  }

  Widget _buildTooltip() {
    final (minMinutes, maxMinutes) = _getTimeRange();
    final range = maxMinutes - minMinutes;
    final minutes =
        _selectedPoint!.time.hour * 60.0 + _selectedPoint!.time.minute;

    return LayoutBuilder(
      builder: (context, constraints) {
        final x = (minutes - minMinutes) / range * constraints.maxWidth;
        final timeStr =
            "${_selectedPoint!.time.hour.toString().padLeft(2, '0')}:${_selectedPoint!.time.minute.toString().padLeft(2, '0')}";
        final valStr = _formatValue(_selectedPoint!.value);

        return Positioned(
          left: (x - 45).clamp(0, constraints.maxWidth - 90),
          top: -45,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.9),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  valStr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatValue(double val) {
    if (val >= 10000) return "${(val / 10000).toStringAsFixed(1)}万";
    return val.toInt().toString();
  }
}

class _ChartPainter extends CustomPainter {
  final List<TrendData> primaryData;
  final List<TrendData>? compareData;
  final TrendData? selectedPoint;

  _ChartPainter(this.primaryData, this.compareData, this.selectedPoint);

  (double, double) _getTimeRange() {
    if (primaryData.isEmpty) return (0.0, 1440.0);

    double min =
        primaryData.first.time.hour * 60.0 + primaryData.first.time.minute;
    double max =
        primaryData.last.time.hour * 60.0 + primaryData.last.time.minute;

    if (compareData != null && compareData!.isNotEmpty) {
      final cMin =
          compareData!.first.time.hour * 60.0 + compareData!.first.time.minute;
      final cMax =
          compareData!.last.time.hour * 60.0 + compareData!.last.time.minute;
      if (cMin < min) min = cMin;
      if (cMax > max) max = cMax;
    }

    min = (min / 60).floor() * 60.0;
    max = (max / 60).ceil() * 60.0;

    if (max - min < 120) {
      max = min + 120;
    }
    if (max > 1440) max = 1440;

    return (min, max);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (primaryData.isEmpty) return;

    final (minMinutes, maxMinutes) = _getTimeRange();
    final timeRange = maxMinutes - minMinutes;

    double minVal = primaryData
        .map((e) => e.value)
        .reduce((a, b) => a < b ? a : b);
    double maxVal = primaryData
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);

    if (compareData != null && compareData!.isNotEmpty) {
      final cMin = compareData!
          .map((e) => e.value)
          .reduce((a, b) => a < b ? a : b);
      final cMax = compareData!
          .map((e) => e.value)
          .reduce((a, b) => a > b ? a : b);
      if (cMin < minVal) minVal = cMin;
      if (cMax > maxVal) maxVal = cMax;
    }

    double range = maxVal - minVal;
    if (range < 1.0) {
      range = (maxVal * 0.1).clamp(10.0, double.infinity);
      minVal -= range / 2;
      maxVal += range / 2;
    }

    final finalRange = maxVal - minVal;
    _drawGrid(canvas, size, minVal, maxVal, minMinutes, maxMinutes);

    if (compareData != null && compareData!.isNotEmpty) {
      _drawLines(
        canvas,
        size,
        compareData!,
        Colors.orange.withOpacity(0.4),
        minVal,
        finalRange,
        minMinutes,
        timeRange,
      );
    }
    _drawLines(
      canvas,
      size,
      primaryData,
      Colors.indigo,
      minVal,
      finalRange,
      minMinutes,
      timeRange,
    );

    if (selectedPoint != null) {
      _drawSelectionHighlight(
        canvas,
        size,
        minVal,
        finalRange,
        minMinutes,
        timeRange,
      );
    }
  }

  void _drawSelectionHighlight(
    Canvas canvas,
    Size size,
    double minVal,
    double range,
    double minMinutes,
    double timeRange,
  ) {
    final minutes =
        selectedPoint!.time.hour * 60.0 + selectedPoint!.time.minute;
    final x = (minutes - minMinutes) / timeRange * size.width;
    final y =
        size.height - ((selectedPoint!.value - minVal) / range * size.height);

    final linePaint = Paint()
      ..color = Colors.indigo.withOpacity(0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

    final outerRing = Paint()
      ..color = Colors.indigo.withOpacity(0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), 8, outerRing);

    final innerDot = Paint()
      ..color = Colors.indigo
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), 4, innerDot);

    final core = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), 2, core);
  }

  void _drawLines(
    Canvas canvas,
    Size size,
    List<TrendData> data,
    Color color,
    double minVal,
    double range,
    double minMinutes,
    double timeRange,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    bool moved = false;
    for (int i = 0; i < data.length; i++) {
      final minutes = data[i].time.hour * 60.0 + data[i].time.minute;
      final x = (minutes - minMinutes) / timeRange * size.width;
      final y = size.height - ((data[i].value - minVal) / range * size.height);
      if (!moved) {
        path.moveTo(x, y);
        moved = true;
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
    }
    canvas.drawPath(path, paint);
  }

  void _drawGrid(
    Canvas canvas,
    Size size,
    double min,
    double max,
    double minMin,
    double maxMin,
  ) {
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.15)
      ..strokeWidth = 1;

    // Horizontal grid
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final labelVal = max - (max - min) * i / 4;
      String labelText = labelVal >= 10000
          ? "${(labelVal / 10000).toStringAsFixed(1)}万"
          : labelVal.toInt().toString();
      _drawText(
        canvas,
        Offset(-42, y - 6),
        labelText,
        const TextStyle(color: Colors.grey, fontSize: 8),
        38,
        TextAlign.right,
      );
    }

    // Vertical grid (Dynamic Time Labels)
    final rangeMin = maxMin - minMin;
    final steps = 4;
    for (var i = 0; i <= steps; i++) {
      final x = size.width * i / steps;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);

      final totalMinutes = minMin + (rangeMin * i / steps);
      final hour = (totalMinutes / 60).floor();
      final minute = (totalMinutes % 60).toInt();
      final label =
          "${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}";

      _drawText(
        canvas,
        Offset(x - 12, size.height + 4),
        label,
        const TextStyle(color: Colors.grey, fontSize: 8),
        24,
        TextAlign.center,
      );
    }
  }

  void _drawText(
    Canvas canvas,
    Offset offset,
    String text,
    TextStyle style,
    double width,
    TextAlign align,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
    );
    tp.layout(minWidth: width, maxWidth: width);
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.primaryData != primaryData ||
        oldDelegate.compareData != compareData ||
        oldDelegate.selectedPoint != selectedPoint;
  }
}
