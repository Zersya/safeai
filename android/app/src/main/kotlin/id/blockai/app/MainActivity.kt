package id.blockai.app

import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.IDN

class MainActivity : FlutterActivity() {
    private val channelName = "id.blockai.app/native"
    private val roleRequestCode = 4242
    private val probeUri: Uri = Uri.parse("https://www.google.com")

    private var channel: MethodChannel? = null
    private var pendingLink: String? = null
    private var pendingRoleResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A recreated activity (savedInstanceState != null) must not replay the old intent.
        if (savedInstanceState == null) {
            pendingLink = taggedText(intent)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> {
                    val text = pendingLink
                    pendingLink = null
                    result.success(text)
                }
                "listBrowsers" -> result.success(listBrowsers())
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url == null) {
                        result.success(false)
                    } else {
                        result.success(openUrl(url, call.argument<String>("package")))
                    }
                }
                "isDefaultBrowser" -> result.success(isDefaultBrowser())
                "requestDefaultBrowser" -> requestDefaultBrowser(result)
                "openDefaultAppsSettings" -> result.success(openDefaultAppsSettings())
                "toAsciiHost" -> {
                    val host = call.argument<String>("host")
                    result.success(
                        try {
                            if (host == null) null else IDN.toASCII(host, IDN.ALLOW_UNASSIGNED)
                        } catch (e: IllegalArgumentException) {
                            null
                        }
                    )
                }
                "moveToBack" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = taggedText(intent)
        if (text != null) {
            channel?.invokeMethod("onNewLink", text)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == roleRequestCode) {
            pendingRoleResult?.success(resultCode == RESULT_OK)
            pendingRoleResult = null
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun taggedText(intent: Intent?): String? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.dataString?.let { "link:$it" }
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)?.let { "share:$it" }
            else -> null
        }
    }

    private fun listBrowsers(): List<Map<String, String>> {
        val probe = Intent(Intent.ACTION_VIEW, probeUri).addCategory(Intent.CATEGORY_BROWSABLE)
        val infos = packageManager.queryIntentActivities(probe, PackageManager.MATCH_ALL)
        val seen = LinkedHashMap<String, String>()
        for (info in infos) {
            val pkg = info.activityInfo.packageName
            if (pkg == packageName || seen.containsKey(pkg)) continue
            seen[pkg] = info.loadLabel(packageManager).toString()
        }
        val chrome = "com.android.chrome"
        val rest = seen.entries.filter { it.key != chrome }.sortedBy { it.value.lowercase() }
        val ordered = ArrayList<Map<String, String>>()
        seen[chrome]?.let { ordered.add(mapOf("package" to chrome, "label" to it)) }
        rest.forEach { ordered.add(mapOf("package" to it.key, "label" to it.value)) }
        return ordered
    }

    private fun isInstalled(pkg: String): Boolean = try {
        packageManager.getPackageInfo(pkg, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun openUrl(url: String, pkg: String?): Boolean {
        return try {
            val view = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            if (pkg != null && isInstalled(pkg)) {
                view.setPackage(pkg).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(view)
            } else {
                val chooser = Intent.createChooser(view, null)
                chooser.putExtra(
                    Intent.EXTRA_EXCLUDE_COMPONENTS,
                    arrayOf(ComponentName(this, MainActivity::class.java))
                )
                startActivity(chooser)
            }
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    private fun isDefaultBrowser(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = getSystemService(RoleManager::class.java)
            return rm != null && rm.isRoleHeld(RoleManager.ROLE_BROWSER)
        }
        val info = packageManager.resolveActivity(
            Intent(Intent.ACTION_VIEW, probeUri), PackageManager.MATCH_DEFAULT_ONLY
        )
        return info?.activityInfo?.packageName == packageName
    }

    private fun requestDefaultBrowser(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = getSystemService(RoleManager::class.java)
            if (rm != null && rm.isRoleAvailable(RoleManager.ROLE_BROWSER)) {
                if (pendingRoleResult != null) {
                    result.success(false)
                    return
                }
                pendingRoleResult = result
                @Suppress("DEPRECATION")
                startActivityForResult(rm.createRequestRoleIntent(RoleManager.ROLE_BROWSER), roleRequestCode)
                return
            }
        }
        openDefaultAppsSettings()
        result.success(false)
    }

    private fun openDefaultAppsSettings(): Boolean = try {
        startActivity(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS))
        true
    } catch (e: Exception) {
        false
    }
}
