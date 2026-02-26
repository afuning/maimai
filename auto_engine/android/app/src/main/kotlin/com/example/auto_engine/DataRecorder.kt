package com.example.auto_engine

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.*

object DataRecorder {
    private const val TAG = "DataRecorder"
    private const val HEADER = "timestamp,containerId,value\n"
    private var filesDir: File? = null

    fun init(context: Context) {
        filesDir = context.filesDir
        Log.d(TAG, "Initialized in: ${filesDir?.absolutePath}")
    }

    private fun getFileForDate(date: Date): File {
        val dateStr = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(date)
        return File(filesDir, "superlike_records_$dateStr.csv")
    }

    fun record(containerId: String, value: String) {
        var now = Date()
        val calendar = Calendar.getInstance()
        calendar.time = now
        
        val hour = calendar.get(Calendar.HOUR_OF_DAY)
        val minute = calendar.get(Calendar.MINUTE)
        
        // If it's 00:00 or 00:01, treat it as 23:59:59 of the previous day
        if (hour == 0 && (minute == 0 || minute == 1)) {
            calendar.add(Calendar.DAY_OF_YEAR, -1)
            calendar.set(Calendar.HOUR_OF_DAY, 23)
            calendar.set(Calendar.MINUTE, 59)
            calendar.set(Calendar.SECOND, 59)
            now = calendar.time
            Log.d(TAG, "Syncing 00:00/01 data to previous day: ${SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(now)}")
        }

        val file = getFileForDate(now)
        
        try {
            if (!file.exists()) {
                file.writeText(HEADER)
                Log.d(TAG, "Created new daily file: ${file.name}")
            }
            
            val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(now)
            val line = "$timestamp,$containerId,$value\n"
            file.appendText(line)
            Log.d(TAG, "Recorded data to ${file.name}: $line")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to record data to ${file.name}", e)
        }
    }

    fun getHistory(): String {
        val result = StringBuilder(HEADER)
        try {
            val listFiles = filesDir?.listFiles { _, name -> 
                name.startsWith("superlike_records_") && name.endsWith(".csv")
            } ?: emptyArray()
            
            // Sort by filename (date) to maintain chronological order
            listFiles.sortedBy { it.name }.forEach { file ->
                val lines = file.readLines()
                if (lines.size > 1) {
                    // Skip header for all files except we already wrote it to StringBuilder
                    lines.drop(1).forEach { line ->
                        if (line.isNotBlank()) {
                            result.append(line).append("\n")
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read history from multiple files", e)
        }
        return result.toString()
    }

    fun updateRecord(timestamp: String, newValue: String): Boolean {
        try {
            // Timestamp format: "2026-02-14 13:53:31"
            val datePart = timestamp.split(" ")[0]
            val file = File(filesDir, "superlike_records_$datePart.csv")
            
            if (!file.exists()) {
                // Return false if updating but file doesn't exist
                // Ideally for manual add we should use addManualRecord
                return false
            }
            
            val lines = file.readLines().toMutableList()
            var modified = false
            
            for (i in lines.indices) {
                // Check if line starts with the exact timestamp
                if (lines[i].startsWith("$timestamp,")) {
                    val parts = lines[i].split(",").toMutableList()
                    if (parts.size >= 3) {
                        parts[2] = newValue
                        lines[i] = parts.joinToString(",")
                        modified = true
                        break 
                    }
                }
            }
            
            if (modified) {
                file.writeText(lines.joinToString("\n") + "\n")
                Log.d(TAG, "Updated record at $timestamp to $newValue")
                return true
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update record", e)
        }
        return false
    }

    fun getAllRecordFiles(): List<String> {
        return filesDir?.listFiles { _, name -> name.startsWith("superlike_records_") && name.endsWith(".csv") }
            ?.map { it.absolutePath }
            ?: emptyList()
    }

    fun addManualRecord(timestamp: String, value: String): Boolean {
        try {
            val datePart = timestamp.split(" ")[0]
            val file = File(filesDir, "superlike_records_$datePart.csv")

            if (!file.exists()) {
                file.writeText(HEADER)
            }
            
            // Read lines and filter out empty ones
            val lines = file.readLines().filter { it.isNotBlank() }.toMutableList()
            
            // Ensure header exists if file was empty
            if (lines.isEmpty()) {
                lines.add(HEADER.trim())
            } else if (lines[0].trim() != HEADER.trim()) {
                 // If first line is not header, we might have a problem or legacy file.
                 // Assuming standard format for now.
            }

            val containerId = "manual_entry"
            val newLine = "$timestamp,$containerId,$value"
            
            // Find insertion point skipping header
            var insertIndex = lines.size
            for (i in 1 until lines.size) {
                 val currentLine = lines[i]
                 val currentTimestamp = currentLine.split(",")[0]
                 if (timestamp < currentTimestamp) {
                     insertIndex = i
                     break
                 }
            }
            
            lines.add(insertIndex, newLine)
            
            file.writeText(lines.joinToString("\n") + "\n")
            Log.d(TAG, "Added manual record sorted: $newLine")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to add manual record", e)
            return false
        }
    }

    fun deleteRecord(timestamp: String): Boolean {
        try {
            val datePart = timestamp.split(" ")[0]
            val file = File(filesDir, "superlike_records_$datePart.csv")
            
            if (!file.exists()) return false
            
            val lines = file.readLines().toMutableList()
            var modified = false
            
            val iterator = lines.iterator()
            while (iterator.hasNext()) {
                val line = iterator.next()
                if (line.startsWith("$timestamp,")) {
                    iterator.remove()
                    modified = true
                    break
                }
            }
            
            if (modified) {
                file.writeText(lines.joinToString("\n") + "\n")
                Log.d(TAG, "Deleted record at $timestamp")
                return true
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to delete record", e)
        }
        return false
    }

    fun getDailyContent(dateStr: String): String {
        try {
            val file = File(filesDir, "superlike_records_$dateStr.csv")
            if (file.exists()) {
                return file.readText()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read daily content", e)
        }
        return ""
    }

    fun saveDailyContent(dateStr: String, content: String): Boolean {
        try {
            val file = File(filesDir, "superlike_records_$dateStr.csv")
            file.writeText(content)
            Log.d(TAG, "Overwrote daily content for $dateStr")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to save daily content", e)
        }
        return false
    }
}
