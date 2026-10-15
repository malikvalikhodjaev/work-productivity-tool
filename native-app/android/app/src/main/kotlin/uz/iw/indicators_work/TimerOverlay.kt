package uz.iw.indicators_work

import android.app.KeyguardManager
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.provider.Settings
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONObject
import java.util.Locale
import kotlin.math.max
import kotlin.math.min

/** Presentation of the existing foreground-service session; never writes time. */
class TimerOverlay(private val context: Context) {
    private val manager = context.getSystemService(WindowManager::class.java)
    private val preferences = context.getSharedPreferences(FocusService.PREFS, Context.MODE_PRIVATE)
    private var root: LinearLayout? = null
    private var clock: TextView? = null
    private var problem: TextView? = null
    private var title: TextView? = null
    private var plan: TextView? = null
    private var source: TextView? = null
    private var sessionId: String? = null

    private fun dp(value: Int) = (value * context.resources.displayMetrics.density).toInt()
    private fun text(size: Float) = TextView(context).apply {
        textSize = size
        setTextColor(Color.rgb(232, 240, 234))
    }

    fun update(snapshot: JSONObject) {
        val active = snapshot.optJSONObject("active")
        val locked = context.getSystemService(KeyguardManager::class.java).isKeyguardLocked
        if (active == null || FocusService.appVisible || locked ||
            !snapshot.optBoolean("overlayEnabled", true) || !Settings.canDrawOverlays(context) ||
            preferences.getString("overlayDismissedSession", null) == active.optString("id")) {
            remove()
            return
        }
        sessionId = active.optString("id")
        if (root == null && !attach()) return
        val now = System.currentTimeMillis() + if (snapshot.optBoolean("local")) 0 else snapshot.optLong("serverOffset")
        val problemData = snapshot.optJSONObject("dailyProblem")
        val problemText = problemData?.opt("text")?.takeIf { it != JSONObject.NULL }?.toString() ?: ""
        problem?.text = "Главная проблема на сегодня\n" + when {
            problemData == null || problemData.optString("date") != FocusService.date(now) || !problemData.optBoolean("loaded") ->
                "No Data · проблема дня ещё не загружена"
            problemText.isBlank() -> "Главная проблема на сегодня не записана"
            else -> problemText
        }
        val elapsed = FocusService.elapsed(active, now)
        val leisure=active.optJSONObject("leisure")
        val seconds = (if(leisure!=null)max(0L,leisure.optLong("until")-now)else if (active.optString("mode") == "pomodoro")
            max(0L, active.optLong("plannedMs") - elapsed) else elapsed) / 1000
        clock?.text = (if (leisure==null&&active.optString("status") == "paused") "Пауза · " else "") +
            if (seconds >= 3600) String.format(Locale.ROOT, "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            else String.format(Locale.ROOT, "%02d:%02d", seconds / 60, seconds % 60)
        val leisureCaption=if(leisure!=null) {
            val time=java.time.Instant.ofEpochMilli(leisure.optLong("until")).atOffset(java.time.ZoneOffset.ofHours(5)).toLocalTime().toString().take(5)
            if(leisure.optLong("until")<=now)"Вернуться к работе?\n"else"Leisure до $time\n"
        }else""
        title?.text = leisureCaption + (if (active.optString("phase") != "work") "Перерыв: "
            else if (active.optString("workRef").startsWith("case:")) "Working on a problem: " else "Working on: ") + active.optString("title")
        val date = FocusService.date(now)
        val rows = snapshot.optJSONArray("pomodoroTargets")
        val counts = snapshot.optJSONArray("pomodoroCounts")
        val day = snapshot.optString("pomodoroDay", snapshot.optString("today"))
        val lines = mutableListOf<String>()
        if (rows != null) for (i in 0 until rows.length()) {
            val row = rows.getJSONObject(i)
            if (row.optString("date") != date || row.isNull("target")) continue
            var actual = 0
            var pending = 0
            if (day == date && counts != null) for (j in 0 until counts.length()) {
                val count = counts.getJSONObject(j)
                if (count.optString("workRef") == row.optString("workRef")) {
                    actual = count.optInt("actualPomodoros")
                    pending = count.optInt("pendingPomodoros")
                }
            }
            val goal = row.optInt("target")
            lines.add("${if (actual >= goal) "☑" else "☐"} ${row.optString("title")} — $actual/$goal" +
                if (pending > 0) " · в очереди $pending" else "")
        }
        plan?.text = if (lines.isEmpty()) "Нормативы на сегодня не заданы" else lines.joinToString("\n\n")
        source?.text = when {
            snapshot.optBoolean("planLocalChanges") -> "Есть локальные изменения"
            !snapshot.optBoolean("planOnline", false) -> "Без связи · последний снимок плана"
            else -> "Общий дневной план"
        }
    }

    private fun attach(): Boolean {
        val metrics = context.resources.displayMetrics
        val width = min(dp(264), metrics.widthPixels - dp(24)).coerceAtLeast(dp(180))
        val panel = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(10), dp(14), dp(14))
            background = GradientDrawable(GradientDrawable.Orientation.TL_BR,
                intArrayOf(Color.rgb(36, 58, 49), Color.rgb(21, 31, 27))).apply { cornerRadius = dp(20).toFloat() }
            elevation = dp(8).toFloat()
            contentDescription = "Плавающий таймер и общий дневной чек-лист"
        }
        val header = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
        val drag = text(12f).apply { text = "I&W · Фокус ⠿"; setPadding(0, dp(10), 0, dp(10)) }
        header.addView(drag, LinearLayout.LayoutParams(0, dp(44), 1f))
        val open = text(22f).apply {
            text = "↗"; gravity = Gravity.CENTER; contentDescription = "Открыть таймер в приложении"
            setOnClickListener { openApp() }
        }
        header.addView(open, LinearLayout.LayoutParams(dp(44), dp(44)))
        val close = text(22f).apply {
            text = "×"; gravity = Gravity.CENTER; contentDescription = "Скрыть малое окно"
            setOnClickListener {
                preferences.edit().putString("overlayDismissedSession", sessionId).apply()
                remove()
            }
        }
        header.addView(close, LinearLayout.LayoutParams(dp(44), dp(44)))
        panel.addView(header)
        problem = text(12f).apply {
            maxLines = 4; ellipsize = TextUtils.TruncateAt.END
            setPadding(0, dp(4), 0, dp(10))
        }
        panel.addView(problem)
        clock = text(38f).apply {
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            setOnClickListener { openApp() }
        }
        panel.addView(clock)
        title = text(13f).apply { maxLines = 3; setPadding(0, dp(4), 0, dp(12)) }
        panel.addView(title)
        panel.addView(text(12f).apply { text = "Помидорки · сегодня"; setTypeface(typeface, Typeface.BOLD) })
        plan = text(12f).apply { setPadding(0, dp(10), 0, dp(8)) }
        val scroll = ScrollView(context).apply { addView(plan) }
        panel.addView(scroll, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT,
            min(dp(118), metrics.heightPixels / 5)))
        source = text(10f).apply { setTextColor(Color.rgb(180, 203, 189)); setPadding(0, dp(6), 0, 0) }
        panel.addView(source)
        val params = WindowManager.LayoutParams(width, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, PixelFormat.TRANSLUCENT).apply {
            gravity = Gravity.TOP or Gravity.START
            x = preferences.getInt("overlayX", dp(16)).coerceIn(0, max(0, metrics.widthPixels - width))
            y = preferences.getInt("overlayY", dp(100)).coerceIn(dp(24), max(dp(24), metrics.heightPixels - dp(380)))
        }
        var startX = 0; var startY = 0; var touchX = 0f; var touchY = 0f
        drag.setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> { startX = params.x; startY = params.y; touchX = event.rawX; touchY = event.rawY; true }
                MotionEvent.ACTION_MOVE -> {
                    params.x = (startX + event.rawX - touchX).toInt().coerceIn(0, max(0, metrics.widthPixels - width))
                    params.y = (startY + event.rawY - touchY).toInt().coerceIn(dp(24), max(dp(24), metrics.heightPixels - panel.height - dp(24)))
                    try { manager.updateViewLayout(panel, params) } catch (_: IllegalArgumentException) { remove() }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    preferences.edit().putInt("overlayX", params.x).putInt("overlayY", params.y).apply()
                    view.performClick(); true
                }
                else -> false
            }
        }
        return try {
            manager.addView(panel, params)
            root = panel; true
        } catch (_: SecurityException) { false }
          catch (_: WindowManager.BadTokenException) { false }
    }

    private fun openApp() {
        try { FocusService.open(context, "timer").send() } catch (_: android.app.PendingIntent.CanceledException) { }
    }

    fun remove() {
        root?.let { try { manager.removeView(it) } catch (_: IllegalArgumentException) { } }
        root = null; clock = null; problem = null; title = null; plan = null; source = null
    }
}
