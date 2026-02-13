package com.example.auto_engine

import android.accessibilityservice.AccessibilityService
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class MyAccessibilityService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        
        // We only care about window state changes or content changes in Weibo
        if (event.packageName != "com.sina.weibo") return
        
        val rootNode = rootInActiveWindow ?: return
        
        // Search for "超like" text
        findAndReportSuperLike(rootNode)
    }

    private fun findAndReportSuperLike(node: AccessibilityNodeInfo) {
        val nodes = node.findAccessibilityNodeInfosByText("超like")
        if (nodes != null && nodes.isNotEmpty()) {
            for (foundNode in nodes) {
                // Usually the number is in the same node or a parent node's sibling
                val text = foundNode.text?.toString() ?: ""
                Log.d("MyAccessibilityService", "Found potential node: $text")
                
                // If the text contains the number (e.g. "1.2万超like"), extract it
                if (text.contains(Regex("\\d"))) {
                    val value = extractValue(text)
                    ScraperScheduler.onScrapeResult(value)
                    return
                }
                
                // Otherwise, look at parent's children (siblings)
                val parent = foundNode.parent
                if (parent != null) {
                    for (i in 0 until parent.childCount) {
                        val child = parent.getChild(i)
                        val childText = child?.text?.toString() ?: ""
                        if (childText.contains(Regex("\\d"))) {
                            val value = extractValue(childText)
                            ScraperScheduler.onScrapeResult(value)
                            return
                        }
                    }
                }
            }
        }
        
        // Recursive search if not found directly by text (safety)
        // Note: findAccessibilityNodeInfosByText is usually enough but for some dynamic layouts...
    }

    private fun extractValue(text: String): String {
        // Simple extraction: digits and dots/unit (like '万')
        val regex = Regex("[0-9.\\u4e00-\\u9fa5]+")
        return regex.find(text)?.value ?: text
    }

    override fun onInterrupt() {
        Log.d("MyAccessibilityService", "Interrupt")
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("MyAccessibilityService", "Service Connected")
    }
}
