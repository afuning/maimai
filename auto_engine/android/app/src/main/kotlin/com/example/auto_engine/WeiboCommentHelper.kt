package com.example.auto_engine

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log

object WeiboCommentHelper {
    private const val TAG = "WeiboCommentHelper"
    const val WAIT_PAGE_LOAD_MS = 3000L
    const val WAIT_AFTER_CLICK_COMMENT_MS = 300L
    const val WAIT_INPUT_POPUP_MS = 1000L
    const val WAIT_INPUT_ACTIVE_MS = 1000L
    const val CLICK_INPUT_TIMEOUT_MS = 3000L
    const val WAIT_BEFORE_SEND_MS = 300L

    // 当前评论任务状态
    var isCommenting = false
        private set
    var isSending = false
        private set
    var pendingComment: String = ""
        private set
    var pendingMid: String = ""
        private set

    // 评论流程阶段
    enum class CommentPhase {
        IDLE,
        WAITING_PAGE_LOAD,    // 等待帖子页面加载
        CLICKING_COMMENT_BUTTON, // 点击评论按钮
        CLICKING_INPUT,       // 点击评论输入框
        WAITING_INPUT_ACTIVE, // 等待输入框激活
        SETTING_TEXT,         // 填入文字
        CLICKING_SEND,        // 点击发送
        DONE                  // 完成
    }

    var phase = CommentPhase.IDLE
        private set

    var startTime = 0L
        private set

    private var resultCallback: ((Boolean) -> Unit)? = null

    fun commentOnPost(context: Context, mid: String, comment: String, callback: (Boolean) -> Unit) {
        if (isCommenting) {
            callback(false)
            return
        }

        isCommenting = true
        pendingMid = mid
        pendingComment = comment
        phase = CommentPhase.WAITING_PAGE_LOAD
        startTime = System.currentTimeMillis()
        resultCallback = callback

        Log.d(TAG, "Starting comment on post: $mid with comment: $comment")

        // 打开微博帖子详情页
        val intent = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse("sinaweibo://detail?mblogid=$mid")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        context.startActivity(intent)
    }

    fun advancePhase(newPhase: CommentPhase) {
        Log.d(TAG, "Phase: $phase -> $newPhase")
        phase = newPhase
        startTime = System.currentTimeMillis()
    }

    fun markSending() {
        isSending = true
        Log.d(TAG, "Mark sending = true")
    }

    fun onCommentSuccess() {
        Log.d(TAG, "Comment success on post: $pendingMid")
        isCommenting = false
        isSending = false
        phase = CommentPhase.DONE
        resultCallback?.invoke(true)
        resultCallback = null
    }

    fun onCommentFailed(reason: String) {
        Log.e(TAG, "Comment failed: $reason")
        isCommenting = false
        isSending = false
        phase = CommentPhase.IDLE
        resultCallback?.invoke(false)
        resultCallback = null
    }

    fun isTimeout(): Boolean {
        return System.currentTimeMillis() - startTime > 20_000 // 20秒超时
    }

    fun reset() {
        isCommenting = false
        isSending = false
        pendingComment = ""
        pendingMid = ""
        phase = CommentPhase.IDLE
        resultCallback = null
    }
}
