import 'dart:convert';
import 'package:http/http.dart' as http;
import 'weibo_models.dart';

class WeiboLinkResolver {
  static final _mWeiboMidReg = RegExp(r'/(\d{16,19})');
  static final _weiboBidReg =
      RegExp(r'weibo\.com/\d+/([A-Za-z0-9]+)');
  static const String _ua =
      'Mozilla/5.0 (Linux; Android 10; Pixel 4) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Mobile Safari/537.36';
  static const weiboVisitorCookie = 'WEIBOCN_FROM=1110006030; SUB=_2AkMex5Nrf8NxqwFRm_gWxGzrbI5_yA3EieKom2KwJRM3HRl-yT9kqhUPtRB6NUe9hBNy0VsgynICiankL2wbA-nAds0g; SUBP=0033WrSXqPxfM72-Ws9jqgMF55529P9D9WWfEMpQl0lQEWP7PKVccJ0i; MLOGIN=0; _T_WM=27872361625; XSRF-TOKEN=da9285; M_WEIBOCN_PARAMS=oid%3D5269209262069485%26luicode%3D20000061%26lfid%3D5269209262069485%26uicode%3D20000061%26fid%3D5269209262069485';
  static final http.Client _client = http.Client();
  /// 对外唯一入口
  static Future<ResolveResult> resolve(String input) async {
    // 1️⃣ t.cn 短链
    if (input.contains('t.cn/')) {
      return _resolveShortUrl(input);
    }

    // 2️⃣ m.weibo.cn / detail / status
    final mid = _extractMidFromMWeibo(input);
    if (mid != null) {
      return ResolveResult.success(mid);
    }

    // 3️⃣ weibo.com 长链（bid）
    final bid = _extractBid(input);
    if (bid != null) {
      final mid = await _bidToMid(bid);
      if (mid != null) {
        return ResolveResult.success(mid);
      }
      return ResolveResult.fail(ResolveFailReason.bidConvertFailed);
    }

    return ResolveResult.fail(ResolveFailReason.invalidUrl);
  }

  // -------- 内部实现 --------

  static String? _extractMidFromMWeibo(String url) {
    final match = _mWeiboMidReg.firstMatch(url);
    return match?.group(1);
  }

  static String? _extractBid(String url) {
    final match = _weiboBidReg.firstMatch(url);
    return match?.group(1);
  }

  static Future<ResolveResult> _resolveShortUrl(String url,
      {int maxRedirect = 3}) async {
    String current = url;

    for (int i = 0; i < maxRedirect; i++) {
      final request = http.Request('GET', Uri.parse(current))
        ..followRedirects = false;
      request.headers['User-Agent'] = _ua;

      final response = await _client.send(request);

      if (response.isRedirect) {
        final location = response.headers['location'];
        if (location == null) return ResolveResult.fail(ResolveFailReason.shortLinkFailed);

        // 处理相对路径
        current = location.startsWith('http')
            ? location
            : Uri.parse(current).resolve(location).toString();
      } else {
        return resolve(current);
      }
    }
    return resolve(current);
  }

  static Future<String?> _bidToMid(String bid) async {
    try {
      final url =
          'https://api.weibo.com/2/statuses/queryid.json?bid=$bid';

      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        },
      );

      if (res.statusCode != 200) return null;

      final json = jsonDecode(res.body);
      return json['data']?['id'];
    } catch (_) {
      return null;
    }
  }
}
