import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  void _handleTap(TapDownDetails details) {
    if (widget.primaryData.isEmpty) return;

    final RenderBox box = context.findRenderObject() as RenderBox;
    final Size size = box.size;
    final Offset localPos = details.localPosition;

    const double maxMinutes = 1440.0;
    TrendData? closest;
    double minDistance = double.infinity;

    for (var data in widget.primaryData) {
      final minutes = data.time.hour * 60.0 + data.time.minute;
      final x = (minutes / maxMinutes) * size.width;
      final distance = (x - localPos.dx).abs();
      if (distance < minDistance) {
        minDistance = distance;
        closest = data;
      }
    }

    // Only select if within a reasonable horizontal distance (e.g., 30px)
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
    const double maxMinutes = 1440.0;
    final minutes =
        _selectedPoint!.time.hour * 60.0 + _selectedPoint!.time.minute;

    return LayoutBuilder(
      builder: (context, constraints) {
        final x = (minutes / maxMinutes) * constraints.maxWidth;
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

  @override
  void paint(Canvas canvas, Size size) {
    if (primaryData.isEmpty) return;

    const double maxMinutes = 1440.0;
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
    _drawGrid(canvas, size, minVal, maxVal);

    if (compareData != null && compareData!.isNotEmpty) {
      _drawLines(
        canvas,
        size,
        compareData!,
        Colors.orange.withOpacity(0.4),
        minVal,
        finalRange,
        maxMinutes,
      );
    }
    _drawLines(
      canvas,
      size,
      primaryData,
      Colors.indigo,
      minVal,
      finalRange,
      maxMinutes,
    );

    if (selectedPoint != null) {
      _drawSelectionHighlight(canvas, size, minVal, finalRange, maxMinutes);
    }
  }

  void _drawSelectionHighlight(
    Canvas canvas,
    Size size,
    double minVal,
    double range,
    double maxMinutes,
  ) {
    final minutes =
        selectedPoint!.time.hour * 60.0 + selectedPoint!.time.minute;
    final x = (minutes / maxMinutes) * size.width;
    final y =
        size.height - ((selectedPoint!.value - minVal) / range * size.height);

    // Vertical guide line
    final linePaint = Paint()
      ..color = Colors.indigo.withOpacity(0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

    // Highlight outer ring
    final outerRing = Paint()
      ..color = Colors.indigo.withOpacity(0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), 8, outerRing);

    // Highlight inner dot
    final innerDot = Paint()
      ..color = Colors.indigo
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), 4, innerDot);

    // White core
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
    double maxMinutes,
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
      final x = (minutes / maxMinutes) * size.width;
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

  void _drawGrid(Canvas canvas, Size size, double min, double max) {
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.15)
      ..strokeWidth = 1;
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

    final timeLabels = ["00:00", "06:00", "12:00", "18:00", "24:00"];
    for (var i = 0; i < timeLabels.length; i++) {
      final x = size.width * i / (timeLabels.length - 1);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      _drawText(
        canvas,
        Offset(x - 12, size.height + 4),
        timeLabels[i],
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
