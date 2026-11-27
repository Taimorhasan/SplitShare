package com.splitshare.app

import android.app.UiModeManager
import android.content.Context
import android.graphics.drawable.ColorDrawable
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applySavedAppearance()
    }

    /**
     * Follows the in-app Appearance setting (Profile → Appearance), which the
     * Flutter side saves as `theme_mode` = light | dark | system.
     *
     * - Android 12+: tells the system, so its launch screen uses the app's
     *   setting from the next launch on.
     * - All versions: paints the window in the right colour straight away,
     *   so the gap before Flutter's first frame matches the app.
     */
    private fun applySavedAppearance() {
        val mode = try {
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.theme_mode", null)
        } catch (e: Exception) {
            null
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val ui = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                ui.setApplicationNightMode(
                    when (mode) {
                        "light" -> UiModeManager.MODE_NIGHT_NO
                        "dark" -> UiModeManager.MODE_NIGHT_YES
                        else -> UiModeManager.MODE_NIGHT_AUTO
                    }
                )
            } catch (e: Exception) {
                // Not critical: the launch screen just follows the phone.
            }
        }

        val colour = when (mode) {
            "light" -> R.color.splash_light
            "dark" -> R.color.splash_dark
            else -> return
        }
        val argb = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            getColor(colour)
        } else {
            @Suppress("DEPRECATION")
            resources.getColor(colour)
        }
        window.setBackgroundDrawable(ColorDrawable(argb))
    }
}
