package com.rinnki.mimao.mimao

import android.view.KeyEvent
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
 */
class MainActivity : FlutterActivity() {
    private val channelName = "mimao/volume"

    /** 当前被授权的 token；null 表示不拦截音量键。 */
    private var activeToken: String? = null
    private var channel: MethodChannel? = null
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
        super.onDestroy()
    }
}
