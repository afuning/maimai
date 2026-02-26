import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_engine/utils/weibo_link_resolver.dart';

class WeiboCommentsPage extends StatefulWidget {
  @override
  _WeiboCommentsPageState createState() => _WeiboCommentsPageState();
}

class _WeiboCommentsPageState extends State<WeiboCommentsPage> {
  static const platform = MethodChannel(
    'com.example.auto_engine/accessibility',
  );

  final TextEditingController _controller = TextEditingController();
  final http.Client _client = http.Client();
  List<Map<String, dynamic>> _results =
      []; // {url, count, status, mid, commented}
  bool _isProcessing = false;
  bool _isCommenting = false; // 批量评论中
  final _rand = Random();

  // 评论模板列表
  List<String> _commentTemplates = [];
  static const String _commentTemplatesKey = 'weibo_comment_templates';

  static const String _ua =
      'Mozilla/5.0 (Linux; Android 10; Pixel 4) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Mobile Safari/537.36';

  @override
  void initState() {
    super.initState();
    _loadCommentTemplates();
  }

  @override
  void dispose() {
    _controller.dispose();
    _client.close();
    super.dispose();
  }

  // ====== 评论模板持久化 ======
  Future<void> _loadCommentTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_commentTemplatesKey) ?? [];
    setState(() => _commentTemplates = list);
  }

  Future<void> _saveCommentTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_commentTemplatesKey, _commentTemplates);
  }

  // ====== 评论模板管理 Dialog ======
  void _showCommentTemplatesDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('评论内容管理'),
                  Text(
                    '${_commentTemplates.length}条',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    Expanded(
                      child: _commentTemplates.isEmpty
                          ? Center(
                              child: Text(
                                '暂无评论内容，点击下方按钮添加',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _commentTemplates.length,
                              itemBuilder: (context, index) {
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            CircleAvatar(
                                              radius: 12,
                                              backgroundColor: Colors.indigo
                                                  .withOpacity(0.1),
                                              child: Text(
                                                '${index + 1}',
                                                style: TextStyle(fontSize: 10),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _commentTemplates[index],
                                                maxLines: 5,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const Divider(height: 16),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _editCommentTemplate(
                                                    index,
                                                    setDlgState,
                                                  ),
                                              icon: const Icon(
                                                Icons.edit,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                '编辑',
                                                style: TextStyle(fontSize: 13),
                                              ),
                                              style: TextButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                    ),
                                                minimumSize: Size.zero,
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            TextButton.icon(
                                              onPressed: () {
                                                setDlgState(() {
                                                  _commentTemplates.removeAt(
                                                    index,
                                                  );
                                                });
                                                _saveCommentTemplates();
                                                setState(() {});
                                              },
                                              icon: const Icon(
                                                Icons.delete,
                                                size: 16,
                                                color: Colors.red,
                                              ),
                                              label: const Text(
                                                '删除',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.red,
                                                ),
                                              ),
                                              style: TextButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                    ),
                                                minimumSize: Size.zero,
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('关闭'),
                ),
                ElevatedButton.icon(
                  icon: Icon(Icons.add, size: 18),
                  label: Text('添加'),
                  onPressed: () => _addCommentTemplate(setDlgState),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _addCommentTemplate(void Function(void Function()) setDlgState) {
    final editCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('添加评论内容'),
          content: TextField(
            controller: editCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: '输入评论内容...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('取消')),
            ElevatedButton(
              onPressed: () {
                final text = editCtrl.text.trim();
                if (text.isNotEmpty) {
                  setDlgState(() {
                    _commentTemplates.add(text);
                  });
                  _saveCommentTemplates();
                  setState(() {});
                  Navigator.pop(ctx);
                }
              },
              child: Text('确定'),
            ),
          ],
        );
      },
    );
  }

  void _editCommentTemplate(
    int index,
    void Function(void Function()) setDlgState,
  ) {
    final editCtrl = TextEditingController(text: _commentTemplates[index]);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('编辑评论内容'),
          content: TextField(
            controller: editCtrl,
            maxLines: 3,
            decoration: InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('取消')),
            ElevatedButton(
              onPressed: () {
                final text = editCtrl.text.trim();
                if (text.isNotEmpty) {
                  setDlgState(() {
                    _commentTemplates[index] = text;
                  });
                  _saveCommentTemplates();
                  setState(() {});
                  Navigator.pop(ctx);
                }
              },
              child: Text('保存'),
            ),
          ],
        );
      },
    );
  }

  // ====== URL 提取 & 评论数获取（保持原有逻辑）======
  List<String> _extractUrls(String text) {
    final regExp = RegExp(
      r'(https?://(?:t\.cn|m\.weibo\.cn|weibo\.com)[^\s]+)',
      caseSensitive: false,
    );
    return regExp.allMatches(text).map((m) => m.group(1)!).toSet().toList();
  }

  Future<String?> resolveShortUrl(String url, {int maxRedirect = 3}) async {
    String current = url;
    for (int i = 0; i < maxRedirect; i++) {
      final request = http.Request('GET', Uri.parse(current))
        ..followRedirects = false;
      request.headers['User-Agent'] = _ua;
      final response = await _client.send(request);
      if (response.isRedirect) {
        final location = response.headers['location'];
        if (location == null) return null;
        current = location.startsWith('http')
            ? location
            : Uri.parse(current).resolve(location).toString();
      } else {
        return current;
      }
    }
    return current;
  }

  Future<int?> parseCommentsFromHtml(String html) async {
    final regRender = RegExp(
      r'\$render_data\s*=\s*(\[\s*\{.*?\}\s*\])',
      dotAll: true,
    );
    final matchRender = regRender.firstMatch(html);
    if (matchRender != null) {
      try {
        final list = jsonDecode(matchRender.group(1)!);
        final status = list[0]['status'];
        return status?['comments_count'];
      } catch (_) {}
    }
    final regInitial = RegExp(
      r'window\.__INITIAL_STATE__\s*=\s*(\{.*?\});',
      dotAll: true,
    );
    final matchInitial = regInitial.firstMatch(html);
    if (matchInitial != null) {
      try {
        final json = jsonDecode(matchInitial.group(1)!);
        return json['status']?['comments_count'];
      } catch (_) {}
    }
    return null;
  }

  Future<int?> fetchCommentsStable(String mid) async {
    final url = 'https://m.weibo.cn/statuses/show?id=$mid';
    final res = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': _ua,
        'Referer': 'https://m.weibo.cn/',
        'Accept': 'application/json',
      },
    );
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body);
    if (json['ok'] != 1) return null;
    return (json['data']?['comments_count'] as num?)?.toInt();
  }

  Future<int?> fetchCommentsCountByApi(String mid) async {
    final url =
        'https://m.weibo.cn/comments/hotflow'
        '?id=$mid&mid=$mid&max_id_type=0';
    const weiboVisitorCookie =
        'WEIBOCN_FROM=1110006030; SUB=_2AkMex5Nrf8NxqwFRm_gWxGzrbI5_yA3EieKom2KwJRM3HRl-yT9kqhUPtRB6NUe9hBNy0VsgynICiankL2wbA-nAds0g; SUBP=0033WrSXqPxfM72-Ws9jqgMF55529P9D9WWfEMpQl0lQEWP7PKVccJ0i; MLOGIN=0; _T_WM=27872361625; XSRF-TOKEN=da9285; M_WEIBOCN_PARAMS=oid%3D5269209262069485%26luicode%3D20000061%26lfid%3D5269209262069485%26uicode%3D20000061%26fid%3D5269209262069485';
    final res = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': _ua,
        'Referer': 'https://m.weibo.cn/status/$mid',
        'Accept': 'application/json',
        'Cookie': weiboVisitorCookie,
      },
    );
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body);
    if (json['ok'] != 1) return null;
    return (json['data']?['total_number'] as num?)?.toInt();
  }

  Future<int?> fetchCommentCount(String mid) async {
    final res = await _client.get(
      Uri.parse('https://m.weibo.cn/detail/$mid'),
      headers: {'User-Agent': _ua, 'Referer': 'https://m.weibo.cn/'},
    );
    if (res.statusCode != 200) return null;
    return parseCommentsFromHtml(res.body);
  }

  // 单个请求逻辑
  Future<void> _fetchSingle(String url) async {
    try {
      final resolved = await WeiboLinkResolver.resolve(url);
      if (!resolved.isSuccess) {
        _updateResult(url, 0, "解析失败: ${resolved.reason?.name}");
        return;
      }
      final weiboId = resolved.mid;
      if (weiboId != null) {
        final count = await fetchCommentsCountByApi(weiboId);
        if (count != null) {
          _updateResult(url, count, "成功", mid: weiboId);
          return;
        }
      }
      _updateResult(url, 0, '获取评论失败:$weiboId');
    } catch (e) {
      _updateResult(url, 0, "错误");
    }
  }

  void _updateResult(String url, int count, String status, {String? mid}) {
    setState(() {
      int index = _results.indexWhere((element) => element['url'] == url);
      if (index != -1) {
        _results[index]['count'] = count;
        _results[index]['status'] = status;
        if (mid != null) {
          _results[index]['mid'] = mid;
        }
      }
    });
  }

  // 批量获取评论数
  Future<void> _startBatchProcess() async {
    List<String> urls = _extractUrls(_controller.text);
    if (urls.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _results = urls.map((u) {
        final existing = _results.firstWhere(
          (r) => r['url'] == u,
          orElse: () => <String, dynamic>{},
        );
        if (existing.isNotEmpty &&
            existing['status'] == '成功' &&
            (existing['count'] as int) >= 25) {
          return existing;
        }
        return <String, dynamic>{
          'url': u,
          'count': 0,
          'status': '等待中...',
          'mid': existing['mid'],
          'commented': existing['commented'] ?? false,
        };
      }).toList();
    });

    for (var url in urls) {
      final item = _results.firstWhere((r) => r['url'] == url);
      if (item['status'] == '成功' && (item['count'] as int) >= 25) {
        continue;
      }
      await _fetchSingle(url);
      await Future.delayed(Duration(milliseconds: 800 + _rand.nextInt(700)));
    }

    setState(() => _isProcessing = false);
  }

  void _copyUnderperforming() {
    final under25 = _results
        .where((r) => r['status'] == '成功' && (r['count'] as int) < 25)
        .toList();
    if (under25.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('没有评论数小于25的帖子')));
      return;
    }

    final buffer = StringBuffer();
    buffer.write(under25.map((item) => _results.indexOf(item) + 1).join(','));

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制 ${under25.length} 条未达标记录')));
  }

  // ====== 无障碍评论功能 ======

  String _getRandomComment() {
    if (_commentTemplates.isEmpty) return '';
    return _commentTemplates[_rand.nextInt(_commentTemplates.length)];
  }

  // 对单条帖子发送评论
  Future<bool> _commentOnPost(String mid) async {
    if (_commentTemplates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请先添加评论内容！')));
      return false;
    }
    final comment = _getRandomComment();
    try {
      final result = await platform.invokeMethod('commentOnPost', {
        'mid': mid,
        'comment': comment,
      });
      return result == true;
    } catch (e) {
      debugPrint("评论失败: $e");
      return false;
    }
  }

  // 单条评论
  Future<void> _commentSingle(int index) async {
    final item = _results[index];
    final mid = item['mid'] as String?;
    if (mid == null || mid.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('该帖子未解析到mid')));
      return;
    }

    setState(() => _isCommenting = true);
    final success = await _commentOnPost(mid);
    setState(() {
      if (success) {
        _results[index]['commented'] = true;
        _results[index]['status'] = '已评论 ✅';
      }
      _isCommenting = false;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(success ? '评论成功！' : '评论失败，请检查日志')));

    // 返回到当前程序
    try {
      await platform.invokeMethod('backToApp');
    } catch (e) {
      debugPrint("返回到程序失败: $e");
    }
  }

  // 批量评论 <25 条帖子（最多5条，按评论数从多到少排序）
  Future<void> _batchComment() async {
    if (_commentTemplates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请先添加评论内容！')));
      return;
    }

    // 筛选：成功 & <25 & 未评论 & 有 mid
    var candidates = _results
        .where(
          (r) =>
              r['status'] == '成功' &&
              (r['count'] as int) < 25 &&
              r['commented'] != true &&
              r['mid'] != null &&
              (r['mid'] as String).isNotEmpty,
        )
        .toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('没有可评论的帖子')));
      return;
    }

    // 按评论数从多到少排序
    candidates.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    // 最多5条
    if (candidates.length > 5) {
      candidates = candidates.sublist(0, 5);
    }

    setState(() => _isCommenting = true);

    int successCount = 0;
    for (int i = 0; i < candidates.length; i++) {
      final item = candidates[i];
      final mid = item['mid'] as String;
      final idx = _results.indexOf(item);

      setState(() {
        _results[idx]['status'] = '评论中...';
      });

      final success = await _commentOnPost(mid);

      setState(() {
        if (success) {
          _results[idx]['commented'] = true;
          _results[idx]['status'] = '已评论 ✅';
          successCount++;
        } else {
          _results[idx]['status'] = '评论失败 ❌';
        }
      });

      // 间隔 10~15 秒
      if (i < candidates.length - 1) {
        await Future.delayed(
          Duration(milliseconds: 10000 + _rand.nextInt(5000)),
        );
      }
    }

    setState(() => _isCommenting = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('批量评论完成：$successCount/${candidates.length} 成功')),
    );

    // 返回到当前程序
    try {
      await platform.invokeMethod('backToApp');
    } catch (e) {
      debugPrint("返回到程序失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final under25Uncommented = _results
        .where(
          (r) =>
              r['status'] == '成功' &&
              (r['count'] as int) < 25 &&
              r['commented'] != true &&
              r['mid'] != null,
        )
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text('微博评论数批量抓取'),
        actions: [
          IconButton(
            icon: Icon(Icons.edit_note),
            tooltip: '评论内容管理',
            onPressed: _showCommentTemplatesDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _controller,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: "粘贴包含微博链接的文字...",
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(Icons.clear),
                  onPressed: () => _controller.clear(),
                ),
              ),
              onChanged: (val) => setState(() {}),
            ),
          ),
          _buildActionButtons(under25Uncommented),
          Divider(),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text("暂无数据", style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      final isCommented = item['commented'] == true;
                      final hasMid =
                          item['mid'] != null &&
                          (item['mid'] as String).isNotEmpty;
                      final canComment =
                          !isCommented &&
                          hasMid &&
                          item['status'] == '成功' &&
                          !_isProcessing &&
                          !_isCommenting;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isCommented
                              ? Colors.green.withOpacity(0.2)
                              : null,
                          child: isCommented
                              ? Icon(Icons.check, color: Colors.green)
                              : Text("${index + 1}"),
                        ),
                        title: Text(
                          item['url'],
                          style: TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          "状态: ${item['status']}",
                          style: TextStyle(
                            color: isCommented ? Colors.green : null,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "${item['count']}",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[800],
                              ),
                            ),
                            SizedBox(width: 8),
                            IconButton(
                              icon: Icon(
                                isCommented ? Icons.check_circle : Icons.send,
                                color: isCommented
                                    ? Colors.green
                                    : (canComment ? Colors.blue : Colors.grey),
                                size: 22,
                              ),
                              tooltip: isCommented ? '已评论' : '评论此帖',
                              onPressed: canComment
                                  ? () => _commentSingle(index)
                                  : null,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(int under25Uncommented) {
    final baseStyle = ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      minimumSize: const Size(0, 36),
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "识别: ${_extractUrls(_controller.text).length} 个",
                style: TextStyle(fontSize: 12, color: Colors.indigo),
              ),
              Text(
                "模板: ${_commentTemplates.length}条",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              ElevatedButton.icon(
                style: baseStyle,
                onPressed: _isProcessing || _isCommenting
                    ? null
                    : _copyUnderperforming,
                icon: Icon(Icons.copy, size: 16),
                label: Text("复制<25"),
              ),
              ElevatedButton.icon(
                style: baseStyle,
                onPressed: _isProcessing || _isCommenting
                    ? null
                    : _startBatchProcess,
                icon: _isProcessing
                    ? SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.play_arrow, size: 18),
                label: Text("开始获取"),
              ),
              ElevatedButton.icon(
                onPressed: _isProcessing || _isCommenting
                    ? null
                    : _batchComment,
                style: baseStyle.copyWith(
                  backgroundColor: MaterialStateProperty.all(Colors.orange),
                  foregroundColor: MaterialStateProperty.all(Colors.white),
                ),
                icon: _isCommenting
                    ? SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(Icons.comment, size: 18),
                label: Text("批量评论($under25Uncommented)"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
