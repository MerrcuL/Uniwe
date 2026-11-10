package org.mercul.uniwe

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Where downloaded documents are stored (shared through
                    // the FileProvider below, see res/xml/document_paths.xml).
                    "directory" -> {
                        val dir = File(cacheDir, "documents").apply { mkdirs() }
                        result.success(dir.absolutePath)
                    }
                    "open", "share" -> {
                        val path = call.argument<String>("path")
                        val mimeType = call.argument<String>("mimeType") ?: "application/pdf"
                        if (path == null) {
                            result.error("ARGS", "path missing", null)
                            return@setMethodCallHandler
                        }
                        result.success(handOver(call.method, File(path), mimeType))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Opens or shares [file]; false if no app can handle it. */
    private fun handOver(action: String, file: File, mimeType: String): Boolean {
        val uri = FileProvider.getUriForFile(this, "$packageName.documents", file)
        val intent = if (action == "open") {
            Intent(Intent.ACTION_VIEW).setDataAndType(uri, mimeType)
        } else {
            Intent.createChooser(
                Intent(Intent.ACTION_SEND)
                    .setType(mimeType)
                    .putExtra(Intent.EXTRA_STREAM, uri)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                null,
            )
        }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    companion object {
        private const val CHANNEL = "org.mercul.uniwe/documents"
    }
}
