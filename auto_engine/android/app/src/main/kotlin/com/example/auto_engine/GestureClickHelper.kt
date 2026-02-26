package com.example.auto_engine

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import kotlin.random.Random

class GestureClickHelper(private val service: AccessibilityService) {

    enum class BottomButton { FORWARD, COMMENT, LIKE }

    /**
     * 点击底部按钮（增加随机偏移和延时，降低安全风险）
     */
    fun clickBottomButton(button: BottomButton, durationMs: Long = 100) {
        val displayMetrics = service.resources.displayMetrics
        val screenWidth = displayMetrics.widthPixels
        val screenHeight = displayMetrics.heightPixels

        // 基础比例坐标
        val baseX = when (button) {
            BottomButton.FORWARD -> 0.15f
            BottomButton.COMMENT -> 0.50f
            BottomButton.LIKE -> 0.85f
        }
        val baseY = 0.95f

        // 随机偏移 ±2% 屏幕宽/高
        val offsetX = screenWidth * Random.nextFloat() * 0.04f - screenWidth * 0.02f
        val offsetY = screenHeight * Random.nextFloat() * 0.04f - screenHeight * 0.02f

        val x = screenWidth * baseX + offsetX
        val y = screenHeight * baseY + offsetY

        // 随机延时 300~1200ms
        val delayMs = Random.nextLong(300, 1200)
        Thread.sleep(delayMs)

        Log.d("GestureClickHelper", "点击底部按钮:($x, $y)")

        clickByCoordinates(x, y, durationMs)
    }

    /**
     * 节点点击，优先 performAction，不可点击 fallback dispatchGesture
     */
    fun clickNode(node: AccessibilityNodeInfo?, fallbackToGesture: Boolean = true) {
        if (node == null) return

        var clickableNode: AccessibilityNodeInfo? = node
        while (clickableNode != null && !clickableNode.isClickable) {
            clickableNode = clickableNode.parent
        }

        if (clickableNode != null) {
            clickableNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            Log.d("GestureClickHelper", "节点点击完成: ${node.text}")
        } else if (fallbackToGesture) {
            val rect = android.graphics.Rect()
            node.getBoundsInScreen(rect)
            clickByCoordinates(
                (rect.left + rect.right) / 2f,
                (rect.top + rect.bottom) / 2f
            )
            Log.d("GestureClickHelper", "不可点击节点，使用手势点击: ${node.text}")
        }
    }

    /**
     * 坐标点击手势
     */
    fun clickByCoordinates(x: Float, y: Float, durationMs: Long = 100) {
        val path = Path().apply { moveTo(x, y) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()

        service.dispatchGesture(
            gesture,
            object : AccessibilityService.GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    super.onCompleted(gestureDescription)
                    Log.d("GestureClickHelper", "手势点击完成: ($x, $y)")
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    super.onCancelled(gestureDescription)
                    Log.d("GestureClickHelper", "手势点击取消: ($x, $y)")
                }
            },
            null
        )
    }

    /**
     * 坐标长按
     */
    fun longPressByCoordinates(x: Float, y: Float, durationMs: Long = 500) {
        clickByCoordinates(x, y, durationMs)
    }
}