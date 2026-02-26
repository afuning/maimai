package com.example.auto_engine

import android.accessibilityservice.AccessibilityService
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.graphics.Rect
import android.content.res.Resources


class MyAccessibilityService : AccessibilityService() {

    private val handler = Handler(Looper.getMainLooper())
    private var isPolling = false
    private val gestureHelper = GestureClickHelper(this)

    private val pollRunnable = object : Runnable {
        override fun run() {
            // ====== 评论模式 ======
            if (WeiboCommentHelper.isCommenting) {
                if (WeiboCommentHelper.isTimeout()) {
                    WeiboCommentHelper.onCommentFailed("评论超时 (20s)")
                    stopPolling()
                    return
                }

                val rootNode = rootInActiveWindow
                if (rootNode != null) {
                    handleCommentFlow(rootNode)
                }
                handler.postDelayed(this, 500)
                return
            }

            // ====== 原有抓取模式 ======
            if (WeiboState.isScrapeCompleted || WeiboState.isTimeout()) {
                stopPolling()
                if (WeiboState.isTimeout() && !WeiboState.isScrapeCompleted) {
                    ScraperScheduler.onScrapeError("轮询超时 (15s)")
                    WeiboState.isScrapeCompleted = true
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

    // ====== 评论自动化流程 ======
    private fun handleCommentFlow(root: AccessibilityNodeInfo) {
        val phase = WeiboCommentHelper.phase
        val elapsed = System.currentTimeMillis() - WeiboCommentHelper.startTime
        Log.d("WeiboComment", "Phase: $phase, elapsed: ${elapsed}ms")

        when (phase) {

            /** ================= 页面加载 ================= */
            WeiboCommentHelper.CommentPhase.WAITING_PAGE_LOAD -> {
                if (elapsed < WeiboCommentHelper.WAIT_PAGE_LOAD_MS) return

                val commentButton = findClickCommentButton(root)
                Log.d("WeiboComment", "找到评论按钮: ${commentButton != null}")
                if (commentButton != null) {
                    WeiboCommentHelper.advancePhase(
                        WeiboCommentHelper.CommentPhase.CLICKING_COMMENT_BUTTON
                    )
                } else {
                    Log.d("WeiboComment", "等待页面加载，未找到评论按钮...")
                    dumpAllNodes(root)
                }
            }

            /** ================= 点击底部评论按钮 ================= */
            WeiboCommentHelper.CommentPhase.CLICKING_COMMENT_BUTTON -> {
                // ⭐ FIX：防止高频重复点击
                if (elapsed < WeiboCommentHelper.WAIT_AFTER_CLICK_COMMENT_MS) return

                gestureHelper.clickBottomButton(GestureClickHelper.BottomButton.COMMENT)
                Log.d("WeiboComment", "点击评论按钮")
                WeiboCommentHelper.advancePhase(
                    WeiboCommentHelper.CommentPhase.WAITING_INPUT_ACTIVE
                )
            }

            /** ================= 点击输入框 ================= */
            WeiboCommentHelper.CommentPhase.CLICKING_INPUT -> {
                if (elapsed < WeiboCommentHelper.WAIT_INPUT_POPUP_MS) return

                val inputNode = findCommentInput(root)
                if (inputNode != null) {
                    val clicked = inputNode.performAction(
                        AccessibilityNodeInfo.ACTION_CLICK
                    )
                    Log.d("WeiboComment", "点击评论输入框: $clicked")

                    if (clicked) {
                        WeiboCommentHelper.advancePhase(
                            WeiboCommentHelper.CommentPhase.WAITING_INPUT_ACTIVE
                        )
                        return
                    }

                    // ⭐ FIX：尝试点击父节点
                    val parent = inputNode.parent
                    if (parent != null && parent.isClickable) {
                        val parentClicked = parent.performAction(
                            AccessibilityNodeInfo.ACTION_CLICK
                        )
                        Log.d("WeiboComment", "点击父节点: $parentClicked")
                        if (parentClicked) {
                            WeiboCommentHelper.advancePhase(
                                WeiboCommentHelper.CommentPhase.WAITING_INPUT_ACTIVE
                            )
                            return
                        }
                    }
                }

                // ⭐ FIX：超时回退，防止卡死
                if (elapsed > WeiboCommentHelper.CLICK_INPUT_TIMEOUT_MS) {
                    Log.d("WeiboComment", "点击输入框超时，回退重新点评论按钮")
                    WeiboCommentHelper.advancePhase(
                        WeiboCommentHelper.CommentPhase.CLICKING_COMMENT_BUTTON
                    )
                }
            }

            /** ================= 等待输入框激活 ================= */
            WeiboCommentHelper.CommentPhase.WAITING_INPUT_ACTIVE -> {
                // ⭐ FIX：这里是严重 bug 修复点
                if (elapsed < WeiboCommentHelper.WAIT_INPUT_ACTIVE_MS) return

                val editText = findEditableNode(root)
                if (editText != null) {
                    WeiboCommentHelper.advancePhase(
                        WeiboCommentHelper.CommentPhase.SETTING_TEXT
                    )
                } else {
                    Log.d("WeiboComment", "等待输入框激活...")
                }
            }

            /** ================= 设置评论文字 ================= */
            WeiboCommentHelper.CommentPhase.SETTING_TEXT -> {
                val editText = findEditableNode(root)
                if (editText != null) {
                    val args = Bundle().apply {
                        putCharSequence(
                            AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                            WeiboCommentHelper.pendingComment
                        )
                    }

                    val setText = editText.performAction(
                        AccessibilityNodeInfo.ACTION_SET_TEXT,
                        args
                    )
                    Log.d(
                        "WeiboComment",
                        "设置评论文字: $setText, content=${WeiboCommentHelper.pendingComment}"
                    )

                    if (setText) {
                        WeiboCommentHelper.advancePhase(
                            WeiboCommentHelper.CommentPhase.CLICKING_SEND
                        )
                    }
                }
            }

            /** ================= 点击发送 ================= */
            WeiboCommentHelper.CommentPhase.CLICKING_SEND -> {
                // ⭐ FIX：避免设置完文本后立刻狂点
                if (elapsed < WeiboCommentHelper.WAIT_BEFORE_SEND_MS) return
                if (WeiboCommentHelper.isSending) return

                val sendBtn = findSendButton(root)
                if (sendBtn != null) {
                    val clicked = sendBtn.performAction(
                        AccessibilityNodeInfo.ACTION_CLICK
                    )
                    Log.d("WeiboComment", "点击发送按钮: $clicked")

                    if (clicked) {
                        WeiboCommentHelper.markSending()
                        handler.postDelayed({
                            WeiboCommentHelper.onCommentSuccess()
                        }, 2000)
                    }
                } else {
                    Log.d("WeiboComment", "未找到发送按钮")
                    dumpAllNodes(root)
                }
            }

            else -> {}
        }
    }

    private fun findClickCommentButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val screenHeight = Resources.getSystem().displayMetrics.heightPixels
        val candidates = mutableListOf<AccessibilityNodeInfo>()
        // 递归收集所有显示纯数字的 TextView（可能是评论或点赞数）
        fun collect(node: AccessibilityNodeInfo) {
            if (node.className == "android.widget.TextView" &&
                node.text?.matches(Regex("\\d+")) == true
            ) {
                candidates.add(node)
            }
            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { collect(it) }
            }
        }

        collect(root)

        if (candidates.isEmpty()) {
            Log.d("WeiboComment", "未找到任何数字节点")
            return null
        }

        // 找最靠屏幕底部的节点（评论通常在中间偏下）
        var target: AccessibilityNodeInfo? = null
        var minDistance = Int.MAX_VALUE
        for (node in candidates) {
            val rect = Rect()
            node.getBoundsInScreen(rect)
            val distance = screenHeight - rect.bottom
            if (distance < minDistance) {
                minDistance = distance
                target = node
            }
        }

        if (target == null) {
            Log.d("WeiboComment", "未找到底部评论数字节点")
            return null
        }

        // 往上找最近可点击父节点
        var clickableNode: AccessibilityNodeInfo? = target
        while (clickableNode != null && !clickableNode.isClickable) {
            clickableNode = clickableNode.parent
        }
        Log.d("WeiboComment", "找到底部评论数字节点: ${target.text}")

        if (clickableNode == null) {
            Log.d("WeiboComment", "未找到可点击父节点")
        } else {
            Log.d("WeiboComment", "找到底部评论按钮父节点: $clickableNode")
        }

        return clickableNode
    }

    private fun findCommentInput(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        // 微博评论输入框常见 hint 文字
        val hints = listOf("写评论", "说点什么", "转发并评论", "评论")
        for (hint in hints) {
            val nodes = root.findAccessibilityNodeInfosByText(hint)
            if (!nodes.isNullOrEmpty()) {
                for (node in nodes) {
                    val text = node.text?.toString() ?: ""
                    val desc = node.contentDescription?.toString() ?: ""
                    if (text.contains(hint) || desc.contains(hint)) {
                        Log.d("WeiboComment", "找到评论输入框: text='$text', desc='$desc'")
                        return node
                    }
                }
            }
        }
        return null
    }

    private fun findEditableNode(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        return findNodeByCondition(root) { node ->
            node.isEditable
        }
    }

    private fun findSendButton(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        // 查找文本包含 "评论" 的所有节点
        val nodes = root.findAccessibilityNodeInfosByText("评论") ?: return null

        // 找到第一个可点击的 TextView 节点，且 text 完全等于 "评论"
        return nodes.firstOrNull { 
            it.className == "android.widget.TextView" && 
            it.isClickable && 
            it.text?.toString() == "评论"
        }
    }

    private fun findNodeByCondition(
        node: AccessibilityNodeInfo?,
        depth: Int = 0,
        condition: (AccessibilityNodeInfo) -> Boolean
    ): AccessibilityNodeInfo? {
        if (node == null || depth > 20) return null
        if (condition(node)) return node
        for (i in 0 until node.childCount) {
            val result = findNodeByCondition(node.getChild(i), depth + 1, condition)
            if (result != null) return result
        }
        return null
    }

    private fun dumpAllNodes(node: AccessibilityNodeInfo?, depth: Int = 0) {
        if (node == null || depth > 15) return

        val rect = Rect()
        node.getBoundsInScreen(rect)

        Log.v(
            "WeiboDump",
            "  ".repeat(depth) +
                "cls='${node.className}', " +
                "text='${node.text}', desc='${node.contentDescription}', " +
                "clickable=${node.isClickable}, " +
                "bounds=$rect"
        )

        for (i in 0 until node.childCount) {
            dumpAllNodes(node.getChild(i), depth + 1)
        }
    }

    private fun dump(node: AccessibilityNodeInfo?, depth: Int = 0) {
        if (node == null) return

        val indent = " ".repeat(depth * 2)
        val rect = android.graphics.Rect()
        node.getBoundsInScreen(rect)

        Log.v(
            "WeiboDump",
            "${indent}cls='${node.className}', " +
            "text='${node.text}', " +
            "desc='${node.contentDescription}', " +
            "clickable=${node.isClickable}, " +
            "bounds=$rect"
        )

        for (i in 0 until node.childCount) {
            dump(node.getChild(i), depth + 1)
        }
    }

    private fun dumpBottomActionBar(root: AccessibilityNodeInfo) {
        fun dfs(node: AccessibilityNodeInfo) {
            if (node.childCount >= 3) {
                val children = (0 until node.childCount)
                    .mapNotNull { node.getChild(it) }

                // 子节点里 TextView 数量
                val textViews = children.count {
                    it.className == "android.widget.TextView"
                }

                if (textViews >= 2) {
                    val rect = android.graphics.Rect()
                    node.getBoundsInScreen(rect)

                    // 位于屏幕下半部分（经验值，非常重要）
                    val screenHeight = Resources.getSystem().displayMetrics.heightPixels
                    if (rect.top > screenHeight * 0.4) {
                        Log.v("WeiboDump", "===== 疑似操作栏 START =====")
                        dump(node)
                        Log.v("WeiboDump", "===== 疑似操作栏 END =====")
                    }
                }
            }

            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { dfs(it) }
            }
        }

        dfs(root)
    }

    // ====== 原有代码保持不变 ======

    private fun startPolling() {
        if (!isPolling) {
            isPolling = true
            handler.post(pollRunnable)
            Log.d("Weibo", "开始主动轮询...")
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
        
        Log.d("WeiboComment", "onArccessibilityEvent")
        // 评论模式：确保轮询启动
        if (WeiboCommentHelper.isCommenting) {
            Log.d("WeiboComment", "评论模式，启动轮询")
            startPolling()
            return
        }

        // 原有抓取模式
        if (!WeiboState.isScrapeCompleted) {
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
        val regex = Regex("[0-9]+(?:\\.[0-9]+)?[\\u4e00-\\u9fa5]?")
        val match = regex.find(text)
        
        if (match != null) {
            return match.value
        }
        
        return text.trim()
    }

    override fun onInterrupt() {
        Log.d("MyAccessibilityService", "Interrupt")
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("MyAccessibilityService", "Service Connected")
        
        ScraperScheduler.init(this)
        
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

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(1001, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(1001, notification)
        }
    }
}
