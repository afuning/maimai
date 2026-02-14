package com.example.auto_engine

import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.provider.Settings
import android.text.TextUtils
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.auto_engine/accessibility"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ScraperScheduler.init(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAccessibilityEnabled" -> {
                    result.success(isAccessibilityServiceEnabled(this, MyAccessibilityService::class.java))
                }
                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                }
                // "openWeibo" -> {
                //     val packageName = "com.sina.weibo"
                //     val launchIntent = Intent().apply {
                //         component = ComponentName(
                //             packageName,
                //             "com.sina.weibo.MainTabActivity"
                //         )
                //         addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                //     }
                //     if (launchIntent != null) {
                //         startActivity(launchIntent)
                //         result.success(true)
                //     } else {
                //         result.error("UNAVAILABLE", "Weibo is not installed", null)
                //     }
                // }
                "startTask" -> {
                    val containerId = call.argument<String>("containerId") ?: ""
                    ScraperScheduler.start(containerId)
                    result.success(true)
                }
                "stopTask" -> {
                    ScraperScheduler.stop()
                    result.success(true)
                }
                "testScrape" -> {
                    val containerId = call.argument<String>("containerId") ?: ""
                    ScraperScheduler.triggerTestScrape(containerId)
                    result.success(true)
                }
                "getTaskStatus" -> {
                    val status = mapOf(
                        "isActive" to ScraperScheduler.isTaskActive,
                        "lastScrapeTime" to ScraperScheduler.lastScrapeTime,
                        "lastScrapeValue" to ScraperScheduler.lastScrapeValue,
                        "lastError" to ScraperScheduler.lastError
                    )
                    result.success(status)
                }
                "getHistory" -> {
                    result.success(DataRecorder.getHistory())
                }
                "updateRecord" -> {
                    val timestamp = call.argument<String>("timestamp") ?: ""
                    val newValue = call.argument<String>("newValue") ?: ""
                    val success = DataRecorder.updateRecord(timestamp, newValue)
                    result.success(success)
                }
                "deleteRecord" -> {
                    val timestamp = call.argument<String>("timestamp") ?: ""
                    val success = DataRecorder.deleteRecord(timestamp)
                    result.success(success)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun isAccessibilityServiceEnabled(context: Context, service: Class<*>): Boolean {
        val expectedComponentName = service.canonicalName
        val enabledServices = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        if (enabledServices == null) return false
        val colonSplitter = TextUtils.SimpleStringSplitter(':')
        colonSplitter.setString(enabledServices)
        while (colonSplitter.hasNext()) {
            val componentName = colonSplitter.next()
            if (componentName.contains(expectedComponentName!!, ignoreCase = true)) {
                return true
            }
        }
        return false
    }
}
