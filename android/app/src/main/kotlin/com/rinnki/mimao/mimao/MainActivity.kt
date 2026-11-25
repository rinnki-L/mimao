package com.rinnki.mimao.mimao

import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 音量键翻页通道（mimao/volume）。
 *
 * 语义对齐 Venera-Next 的 venera/volume：Dart 侧按 token 申请/撤销监听，
 * 原生侧只对持有 token 的调用者回调 `event`（1 = 上一页，2 = 下一页）。
 * 未授权时音量键保持系统行为（正常调节音量）。
 *
 * 只拦截按下（ACTION_DOWN），并吞掉配对的 ACTION_UP，避免系统音量条闪一下；
 * 长按产生的重复事件忽略，避免一次长按连翻十几页。
 *
 * 显示能力通道（mimao/display）：
 * - setBrightness(Double?)：null = 交还系统（跟随系统亮度）；0..1 = 本窗口亮度。
 *   改的是 window.attributes.screenBrightness（窗口级，不需要 WRITE_SETTINGS，
 *   Activity 销毁即自动恢复），不是 Settings.System 的全局亮度。
 * - keepAwake(Boolean)：FLAG_KEEP_SCREEN_ON（不改系统休眠设置，退出即失效）。
 *
 * 小说阅读器与漫画阅读器共用这两条通道；桌面上 Dart 侧走 no-op，通道不会被调用。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "mimao/volume"
    private val displayChannelName = "mimao/display"

    /** 当前被授权的 token；null 表示不拦截音量键。 */
    private var activeToken: String? = null
    private var channel: MethodChannel? = null
    private var displayChannel: MethodChannel? = null
    private var swallowUpFor: Int? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        )
        channel = methodChannel
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "listen" -> {
                    activeToken = call.argument<String>("token")
                    result.success(null)
                }
                "cancel" -> {
                    val token = call.argument<String>("token")
                    // 只允许撤销自己的 token，避免旧租约撤销新租约。
                    if (token != null && token == activeToken) {
                        activeToken = null
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        val display = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            displayChannelName,
        )
        displayChannel = display
        display.setMethodCallHandler { call, result ->
            when (call.method) {
                "setBrightness" -> {
                    val raw = call.argument<Double>("value")
                    window.attributes = window.attributes.apply {
                        screenBrightness = raw?.toFloat()?.coerceIn(0f, 1f)
                            ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                    }
                    result.success(null)
                }
                "keepAwake" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (enabled) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val token = activeToken ?: return super.dispatchKeyEvent(event)
        val keyCode = event.keyCode
        if (keyCode != KeyEvent.KEYCODE_VOLUME_UP && keyCode != KeyEvent.KEYCODE_VOLUME_DOWN) {
            return super.dispatchKeyEvent(event)
        }
        when (event.action) {
            KeyEvent.ACTION_DOWN -> {
                if (event.repeatCount == 0) {
                    val value = if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) 2 else 1
                    channel?.invokeMethod(
                        "event",
                        mapOf("token" to token, "value" to value),
                    )
                }
                swallowUpFor = keyCode
                return true
            }
            KeyEvent.ACTION_UP -> {
                if (swallowUpFor == keyCode) {
                    swallowUpFor = null
                    return true
                }
                return super.dispatchKeyEvent(event)
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onDestroy() {
        channel?.setMethodCallHandler(null)
        channel = null
        activeToken = null
        displayChannel?.setMethodCallHandler(null)
        displayChannel = null
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onDestroy()
    }
}
