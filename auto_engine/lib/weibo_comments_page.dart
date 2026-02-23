import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:auto_engine/utils/weibo_link_resolver.dart';

class WeiboCommentsPage extends StatefulWidget {
  @override
  _WeiboCommentsPageState createState() => _WeiboCommentsPageState();
}

class _WeiboCommentsPageState extends State<WeiboCommentsPage> {
  final TextEditingController _controller = TextEditingController();
  final http.Client _client = http.Client();
  List<Map<String, dynamic>> _results = []; // 存储 {url: string, count: int, status: string}
  bool _isProcessing = false;
  final _rand = Random();
  static const String _ua =
      'Mozilla/5.0 (Linux; Android 10; Pixel 4) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Mobile Safari/537.36';
  @override
  void dispose() {
    _controller.dispose();
    _client.close();
    super.dispose();
  }

  // 正则提取链接
  List<String> _extractUrls(String text) {
    final regExp = RegExp(
      r'(https?://(?:t\.cn|m\.weibo\.cn|weibo\.com)[^\s]+)',
      caseSensitive: false,
    );

    return regExp
        .allMatches(text)
        .map((m) => m.group(1)!)
        .toSet()
        .toList();
  }

  /// ===============================
  /// 1. 解 t.cn 短链（支持多级 302）
  /// ===============================
  Future<String?> resolveShortUrl(String url,
      {int maxRedirect = 3}) async {
    String current = url;

    for (int i = 0; i < maxRedirect; i++) {
      final request = http.Request('GET', Uri.parse(current))
        ..followRedirects = false;
      request.headers['User-Agent'] = _ua;

      final response = await _client.send(request);

      if (response.isRedirect) {
        final location = response.headers['location'];
        if (location == null) return null;

        // 处理相对路径
        current = location.startsWith('http')
            ? location
            : Uri.parse(current).resolve(location).toString();
      } else {
        return current;
      }
    }
    return current;
  }

  /// ===============================
  /// 3. 获取评论数
  /// ===============================
  Future<int?> parseCommentsFromHtml(String html) async {
    // 1️⃣ 新版：$render_data = [ {...} ]
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

    // 2️⃣ 旧版兜底：__INITIAL_STATE__
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
    const weiboVisitorCookie = 'WEIBOCN_FROM=1110006030; SUB=_2AkMex5Nrf8NxqwFRm_gWxGzrbI5_yA3EieKom2KwJRM3HRl-yT9kqhUPtRB6NUe9hBNy0VsgynICiankL2wbA-nAds0g; SUBP=0033WrSXqPxfM72-Ws9jqgMF55529P9D9WWfEMpQl0lQEWP7PKVccJ0i; MLOGIN=0; _T_WM=27872361625; XSRF-TOKEN=da9285; M_WEIBOCN_PARAMS=oid%3D5269209262069485%26luicode%3D20000061%26lfid%3D5269209262069485%26uicode%3D20000061%26fid%3D5269209262069485';
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
      headers: {
        'User-Agent': _ua,
        'Referer': 'https://m.weibo.cn/',
      },
    );


    if (res.statusCode != 200) return null;

    return parseCommentsFromHtml(res.body);
  }

  // 单个请求逻辑
  Future<void> _fetchSingle(String url) async {
    try {
      // 1. 解析链接获取 mid
      final resolved = await WeiboLinkResolver.resolve(url);
      if (!resolved.isSuccess) {
        _updateResult(url, 0, "解析失败: ${resolved.reason?.name}");
        return;
      }
      final weiboId = resolved.mid;

      // 2. 请求微博 API
      if (weiboId != null) {
        final count = await fetchCommentsCountByApi(weiboId);
        if (count != null) {
          _updateResult(url, count, "成功");
          return;
        }
      }
      _updateResult(url, 0, '获取评论失败:$weiboId');
    } catch (e) {
      _updateResult(url, 0, "错误");
    }
  }

  void _updateResult(String url, int count, String status) {
    setState(() {
      int index = _results.indexWhere((element) => element['url'] == url);
      if (index != -1) {
        _results[index] = <String, dynamic>{'url': url, 'count': count, 'status': status};
      }
    });
  }

  // 批量执行逻辑
  Future<void> _startBatchProcess() async {
    List<String> urls = _extractUrls(_controller.text);
    if (urls.isEmpty) return;

    setState(() {
      _isProcessing = true;
      // 保留已达到25评的记录状态
      _results = urls.map((u) {
        final existing = _results.firstWhere((r) => r['url'] == u, orElse: () => <String, dynamic>{});
        if (existing.isNotEmpty && existing['status'] == '成功' && (existing['count'] as int) >= 25) {
           return existing;
        }
        return <String, dynamic>{'url': u, 'count': 0, 'status': '等待中...'};
      }).toList();
    });

    for (var url in urls) {
      final item = _results.firstWhere((r) => r['url'] == url);
      // 跳过已达到25评的记录
      if (item['status'] == '成功' && (item['count'] as int) >= 25) {
        continue;
      }
      
      await _fetchSingle(url);
      // 间隔 1.5 秒防封
      await Future.delayed(Duration(milliseconds: 1500 + _rand.nextInt(1500)));
    }

    setState(() => _isProcessing = false);
  }

  void _copyUnderperforming() {
    final under25 = _results.where((r) => r['status'] == '成功' && (r['count'] as int) < 25).toList();
    if (under25.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('没有评论数小于25的帖子')));
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('===== 评论未达标 (${under25.length}条) =====');
    for (var i = 0; i < under25.length; i++) {
      final item = under25[i];
      // Find the original index of this item in the _results list
      final originalIndex = _results.indexOf(item) + 1;
      buffer.writeln('第$originalIndex条: ${item['count']}评');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制 ${under25.length} 条未达标记录')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('微博评论数批量抓取')),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("识别: ${_extractUrls(_controller.text).length} 个"),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _copyUnderperforming,
                      icon: Icon(Icons.copy, size: 18),
                      label: Text("复制<25"),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _startBatchProcess,
                      icon: _isProcessing ? SizedBox(width:12, height:12, child: CircularProgressIndicator(strokeWidth: 2)) :     Icon(Icons.play_arrow),
                      label: Text("开始获取"),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(),
          Expanded(
            child: _results.isEmpty 
              ? Center(child: Text("暂无数据", style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final item = _results[index];
                    return ListTile(
                      leading: CircleAvatar(child: Text("${index + 1}")),
                      title: Text(item['url'], style: TextStyle(fontSize: 13)),
                      subtitle: Text("状态: ${item['status']}"),
                      trailing: Text(
                        "${item['count']}",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange[800]),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}