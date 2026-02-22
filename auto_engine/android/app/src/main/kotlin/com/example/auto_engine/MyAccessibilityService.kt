package com.example.auto_engine

import android.accessibilityservice.AccessibilityService
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class MyAccessibilityService : AccessibilityService() {

    private val handler = Handler(Looper.getMainLooper())
    private var isPolling = false

    private val pollRunnable = object : Runnable {
        override fun run() {
            if (WeiboState.hasReadLike || WeiboState.isTimeout()) {
                stopPolling()
                if (WeiboState.isTimeout() && !WeiboState.hasReadLike) {
                    ScraperScheduler.onScrapeError("轮询超时 (15s)")
                    WeiboState.hasReadLike = true
                }
                return
            }

            val rootNode = rootInActiveWindow
            if (rootNode != null) {
                if (WeiboState.isReady()) {
                    if (findAndReportSuperLike(rootNode)) {
                        stopPolling()
                        return
                    }

                    if (!WeiboState.hasClickedExpand) {
                        if (clickExpandMore(rootNode)) {
                            WeiboState.hasClickedExpand = true
                        }
                    }
                }
            }

            handler.postDelayed(this, 500)
        }
    }

    private fun startPolling() {
        if (!isPolling) {
            isPolling = true
            handler.post(pollRunnable)
            Log.d("Weibo", "开始主动轮询抓取任务...")
        }
    }

    private fun stopPolling() {
        isPolling = false
        handler.removeCallbacks(pollRunnable)
        Log.d("Weibo", "结束轮询任务。")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.packageName != "com.sina.weibo") return
        
        // When we see a Weibo event, ensure polling is started if we haven't finished the task
        if (!WeiboState.hasReadLike) {
            startPolling()
        }
    }

    private fun clickExpandMore(root: AccessibilityNodeInfo): Boolean {
        Log.d("Weibo", "开始尝试点击展开图标...")
        val nodes = root.findAccessibilityNodeInfosByText("expand")
        
        if (nodes.isNullOrEmpty()) {
            Log.w("Weibo", "未找到针对 'expand' 的节点")
            return false
        }

        for (node in nodes) {
            val desc = node.contentDescription?.toString() ?: ""
            val text = node.text?.toString() ?: ""
            
            if ((desc.contains("expand", ignoreCase = true) || text.contains("expand", ignoreCase = true))
                && node.isClickable
            ) {
                val success = node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                Log.d("Weibo", "执行点击 expand: $success")
                return success
            }
        }
        return false
    }

    private fun dumpNodes(node: AccessibilityNodeInfo?, depth: Int = 0) {
        if (node == null || depth > 20) return
        val desc = node.contentDescription?.toString() ?: ""
        val text = node.text?.toString() ?: ""
        if (desc.isNotEmpty() || text.isNotEmpty()) {
            Log.v("WeiboDump", "  ".repeat(depth) + "Node: text='$text', desc='$desc', clickable=${node.isClickable}, viewId=${node.viewIdResourceName}")
        }
        for (i in 0 until node.childCount) {
            dumpNodes(node.getChild(i), depth + 1)
        }
    }

    private fun findAndReportSuperLike(node: AccessibilityNodeInfo): Boolean {
        val nodes = node.findAccessibilityNodeInfosByText("超like")
        if (!nodes.isNullOrEmpty()) {
            for (foundNode in nodes) {
                val text = foundNode.text?.toString() ?: ""
                Log.d("MyAccessibilityService", "Found potential node: $text")
                
                // Case A: number is in the same node
                if (text.contains(Regex("\\d"))) {
                    val value = extractValue(text)
                    ScraperScheduler.onScrapeResult(value)
                    return true
                }
                
                // Case B: number is in a sibling node
                val parent = foundNode.parent
                if (parent != null) {
                    for (i in 0 until parent.childCount) {
                        val child = parent.getChild(i)
                        val childText = child?.text?.toString() ?: ""
                        if (childText.contains(Regex("\\d"))) {
                            val value = extractValue(childText)
                            ScraperScheduler.onScrapeResult(value)
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    private fun extractValue(text: String): String {
        // Find the first sequence that starts with a digit
        // Supports integers, decimals, and optional Chinese units like '万'
        val regex = Regex("[0-9]+(?:\\.[0-9]+)?[\\u4e00-\\u9fa5]?")
        val match = regex.find(text)
        
        if (match != null) {
            return match.value
        }
        
        // Fallback: if no digits found, but we are here, just return the original trimmed text
        return text.trim()
    }

    override fun onInterrupt() {
        Log.d("MyAccessibilityService", "Interrupt")
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("MyAccessibilityService", "Service Connected")
        
        // Optimize: Move Scheduler init here
        ScraperScheduler.init(this)
        
        // Start as Foreground Service
        startForegroundService()
    }

    override fun onDestroy() {
        super.onDestroy()
        ScraperScheduler.stop()
        Log.d("MyAccessibilityService", "Service Destroyed")
    }

    private fun startForegroundService() {
        val channelId = "auto_engine_service"
        val channelName = "Auto Engine Background Service"
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val chan = android.app.NotificationChannel(channelId, channelName, android.app.NotificationManager.IMPORTANCE_LOW)
            val manager = getSystemService(android.app.NotificationManager::class.java)
            manager.createNotificationChannel(chan)
        }

        val notification = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, channelId)
                .setContentTitle("Auto Engine Running")
                .setContentText("Keeping accessibility service active")
                .setSmallIcon(R.mipmap.ic_launcher)
                .build()
        } else {
             android.app.Notification.Builder(this)
                .setContentTitle("Auto Engine Running")
                .setContentText("Keeping accessibility service active")
                .setSmallIcon(R.mipmap.ic_launcher)
                .build()
        }

        startForeground(1001, notification)
    }
}
