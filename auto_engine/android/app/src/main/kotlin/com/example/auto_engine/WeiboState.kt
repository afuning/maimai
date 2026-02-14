package com.example.auto_engine

object WeiboState {

    var hasClickedExpand = false
    var hasReadLike = false
    var startTime = System.currentTimeMillis()

    fun reset() {
        hasClickedExpand = false
        hasReadLike = false
        startTime = System.currentTimeMillis()
    }

    fun isReady(): Boolean {
        return System.currentTimeMillis() - startTime > 2_000
    }

    fun isTimeout(): Boolean {
        return System.currentTimeMillis() - startTime > 15_000
    }
}