package com.example.auto_engine

import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.text.SimpleDateFormat
import java.util.*

object ScraperScheduler {
    private const val TAG = "ScraperScheduler"
    private const val INTERVAL_MS = 30 * 60 * 1000L // 30 minutes
    
    var isTaskActive = false
        private set
        
    var containerId: String = ""
    var lastScrapeTime: Long = 0
    var lastScrapeValue: String = "N/A"
    
    private val handler = Handler(Looper.getMainLooper())
    private var context: Context? = null

    private val checkTaskRunnable = object : Runnable {
        override fun run() {
            if (!isTaskActive) return
            
            val now = System.currentTimeMillis()
            if (shouldScrape(now)) {
                performScrape()
            }
            
            // Check again every minute for precision (especially for 00:00)
            handler.postDelayed(this, 60 * 1000L)
        }
    }

    fun init(context: Context) {
        this.context = context.applicationContext
    }

    fun start(id: String) {
        if (isTaskActive) return
        containerId = id
        isTaskActive = true
        Log.d(TAG, "Scheduler started with containerId: $containerId")
        handler.post(checkTaskRunnable)
    }

    fun stop() {
        isTaskActive = false
        handler.removeCallbacks(checkTaskRunnable)
        Log.d(TAG, "Scheduler stopped")
    }

    fun triggerTestScrape(id: String) {
        val originalId = containerId
        containerId = id
        performScrape()
        // Restore ID if it was different, although usually it's the same
        if (originalId.isNotEmpty()) {
            containerId = originalId
        }
    }

    private fun shouldScrape(now: Long): Boolean {
        // Condition 1: 30 minutes since last scrape
        // Add random jitter (-2 to +2 minutes)
        val jitter = Random().nextInt(4 * 60 * 1000) - (2 * 60 * 1000)
        val timeSinceLast = now - lastScrapeTime
        if (timeSinceLast >= (INTERVAL_MS + jitter)) return true
        
        // Condition 2: 00:00 requirement
        val sdf = SimpleDateFormat("HH:mm", Locale.getDefault())
        val currentTimeStr = sdf.format(Date(now))
        if (currentTimeStr == "00:00" || currentTimeStr == "00:01") {
            // Check if we already scraped in the last 10 minutes to avoid double capture
            if (now - lastScrapeTime > 10 * 60 * 1000L) return true
        }
        
        return false
    }

    private fun performScrape() {
        if (containerId.isEmpty()) return
        
        Log.d(TAG, "Triggering scrape for $containerId")
        val intent = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse("sinaweibo://container/getIndex?containerid=$containerId")
            component = ComponentName("com.sina.weibo", "com.sina.weibo.supergroup.SGPageActivity")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context?.startActivity(intent)
    }

    fun onScrapeResult(value: String) {
        lastScrapeValue = value
        lastScrapeTime = System.currentTimeMillis()
        Log.d(TAG, "Scrape result: $value at $lastScrapeTime")
    }
}
