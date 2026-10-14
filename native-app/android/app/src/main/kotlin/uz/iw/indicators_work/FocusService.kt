package uz.iw.indicators_work

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.*
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import java.net.URL
import java.time.*
import java.time.format.DateTimeFormatter
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

class FocusService : Service() {
    companion object {
        const val PREFS = "iw_background"
        const val CHANNEL = "iw_focus"
        const val ALERTS = "iw_alerts"
        const val ONGOING = 101
        const val TIMER_ALERT = 102
        const val DAILY_ALERT = 103
        fun channels(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(CHANNEL,"Таймер в фоне",NotificationManager.IMPORTANCE_LOW))
            manager.createNotificationChannel(NotificationChannel(ALERTS,"Помидорки и дневные нормативы",NotificationManager.IMPORTANCE_HIGH))
        }
        fun date(now: Long) = Instant.ofEpochMilli(now).atOffset(ZoneOffset.ofHours(5)).toLocalDate().toString()
        fun elapsed(s: JSONObject, now: Long): Long {
            var past = 0L
            val intervals = s.optJSONArray("intervals") ?: JSONArray()
            for (i in 0 until intervals.length()) { val interval = intervals.getJSONObject(i); past += interval.getLong("end") - interval.getLong("start") }
            val running = if(s.optString("status")=="running") max(0L, now-s.optLong("runningSince")) else 0L
            return past + if(s.optString("mode")=="pomodoro") min(running,max(0L,s.optLong("plannedMs")-past)) else running
        }
        fun open(context: Context, screen: String): PendingIntent = PendingIntent.getActivity(context,screen.hashCode(),Intent(context,MainActivity::class.java).putExtra("iw_screen",screen).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun alert(context: Context, timer: Boolean) {
            channels(context)
            val prefs=context.getSharedPreferences(PREFS,MODE_PRIVATE)
            val data=JSONObject(prefs.getString("snapshot","{}") ?: "{}")
            val currentDate=date(System.currentTimeMillis())
            val plans=data.optJSONArray("pomodoroTargets")?:JSONArray()
            val counts=data.optJSONArray("pomodoroCounts")?:JSONArray()
            val lines=mutableListOf<String>()
            for(i in 0 until plans.length()) {
                val n=plans.getJSONObject(i)
                if(n.optString("date")!=currentDate||n.isNull("target"))continue
                var actual=0
                if(data.optString("today")==currentDate)for(j in 0 until counts.length()) {
                    val c=counts.getJSONObject(j);if(c.optString("workRef")==n.optString("workRef"))actual=c.optInt("actualPomodoros")
                }
                lines.add("${n.optString("title")} — $actual/${n.optInt("target")}")
            }
            val title=if(timer)"Как прошла помидорка?" else if(data.optBoolean("planningReady")&&lines.isEmpty())"Вы поставили нормативы на день?" else "Сделал это?"
            val body=if(timer)data.optJSONObject("active")?.optString("title") ?: "Запиши наблюдение и уточни минуты" else if(lines.isNotEmpty())lines.joinToString("\n") else "Открой настройки и задай норматив помидорок на сегодня"
            val notification=Notification.Builder(context,ALERTS).setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle(title).setContentText(body).setStyle(Notification.BigTextStyle().bigText(body)).setContentIntent(open(context,if(timer)"timer" else "norms")).setAutoCancel(true).build()
            context.getSystemService(NotificationManager::class.java).notify(if(timer)TIMER_ALERT else DAILY_ALERT,notification)
        }
        fun schedule(context: Context, data: JSONObject) {
            channels(context)
            val manager=context.getSystemService(AlarmManager::class.java)
            fun alarm(kind: String, at: Long?) {
                val intent=PendingIntent.getBroadcast(context,kind.hashCode(),Intent(context,ReminderReceiver::class.java).putExtra("kind",kind),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                manager.cancel(intent)
                if(at==null)return
                val timestamp=max(System.currentTimeMillis()+1000,at)
                if(Build.VERSION.SDK_INT<31||manager.canScheduleExactAlarms()) manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,timestamp,intent)
                else manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,timestamp,intent)
            }
            val active=data.optJSONObject("active")
            val now=System.currentTimeMillis()
            val offset=if(data.optBoolean("local"))0L else data.optLong("serverOffset")
            val remaining=if(active!=null&&active.optString("status")=="running"&&active.optString("mode")=="pomodoro")max(0L,active.optLong("plannedMs")-elapsed(active,now+offset))else null
            alarm("timer",if(remaining!=null&&remaining>0)now+remaining else null)
            var next: Long?=null
            val norms=data.optJSONArray("norms")?:JSONArray()
            val checks=data.optJSONArray("checks")?:JSONArray()
            val hidden=data.optJSONObject("hidden")?:JSONObject()
            val currentDate=date(now)
            for(i in 0 until norms.length()) {
                val n=norms.getJSONObject(i)
                if(!n.optBoolean("enabled")||n.isNull("minutes"))continue
                val ref=n.getString("workRef")
                val actual=if(data.optString("today")==currentDate)n.optDouble("actualMinutes",0.0)else 0.0
                var confirmed=false
                for(j in 0 until checks.length()){val c=checks.getJSONObject(j);if(c.optString("date")==currentDate&&c.optString("workRef")==ref&&c.optBoolean("confirmed"))confirmed=true}
                val days=n.optJSONArray("days")?:JSONArray("[1,2,3,4,5,6,7]")
                for(day in 0..7){
                    val local=Instant.ofEpochMilli(now).atOffset(ZoneOffset.ofHours(5)).toLocalDate().plusDays(day.toLong())
                    if(day==0&&(confirmed||actual>=n.getDouble("minutes")))continue
                    var applies=false
                    for(d in 0 until days.length())if(days.optInt(d)==local.dayOfWeek.value)applies=true
                    if(!applies)continue
                    val anchor=local.atTime(LocalTime.parse(n.optString("time","09:00"),DateTimeFormatter.ofPattern("HH:mm"))).toInstant(ZoneOffset.ofHours(5)).toEpochMilli()
                    val until=hidden.optLong("$local:$ref",0L)
                    var due=anchor
                    val threshold=max(now,until)
                    if(due<threshold)due+=((threshold-due+3599999L)/3600000L)*3600000L
                    if(Instant.ofEpochMilli(due).atOffset(ZoneOffset.ofHours(5)).toLocalDate()!=local)continue
                    if(next==null||due<next!!)next=due
                    break
                }
            }
            if(data.optBoolean("planningReady")) {
                val plans=data.optJSONArray("pomodoroTargets")?:JSONArray()
                val counts=data.optJSONArray("pomodoroCounts")?:JSONArray()
                var hasPlan=false;var unfinished=false
                for(i in 0 until plans.length()) {
                    val n=plans.getJSONObject(i)
                    if(n.optString("date")!=currentDate||n.isNull("target"))continue
                    hasPlan=true;var actual=0
                    if(data.optString("today")==currentDate)for(j in 0 until counts.length()) {
                        val c=counts.getJSONObject(j);if(c.optString("workRef")==n.optString("workRef"))actual=c.optInt("actualPomodoros")
                    }
                    if(actual<n.optInt("target"))unfinished=true
                }
                val prefs=context.getSharedPreferences(PREFS,MODE_PRIVATE)
                val hiddenPom=if(data.optString("today")==currentDate)data.optLong("pomodoroHiddenUntil")else 0L
                val due=if(!hasPlan||unfinished)max(now+1000,max(hiddenPom,prefs.getLong("pomodoroReminder:$currentDate",0)))
                    else Instant.ofEpochMilli(now).atOffset(ZoneOffset.ofHours(5)).toLocalDate().plusDays(1).atStartOfDay().toInstant(ZoneOffset.ofHours(5)).toEpochMilli()
                if(next==null||due<next!!)next=due
            }
            alarm("norms",next)
        }
    }
    private val handler=Handler(Looper.getMainLooper())
    private val network=Executors.newSingleThreadExecutor()
    private var player: MediaPlayer?=null
    private var playing: String?=null
    private var snapshot=JSONObject()
    private var count=0
    private var fetching=false
    private val tick=object:Runnable{
        override fun run(){
            val active=snapshot.optJSONObject("active")
            val offset=if(snapshot.optBoolean("local"))0L else snapshot.optLong("serverOffset")
            var title="Indicators & Work Dashboard"
            var detail="Фоновый звук"
            if(active!=null){
                val now=System.currentTimeMillis()+offset
                val amount=elapsed(active,now)
                val remaining=if(active.optString("mode")=="pomodoro")max(0L,active.optLong("plannedMs")-amount)else amount
                val seconds=remaining/1000
                title="%02d:%02d".format(seconds/60,seconds%60)
                val prefix=if(active.optString("workRef").startsWith("case:"))"Working on a problem: "else"Working on: "
                detail=prefix+active.optString("title")
                if(active.optString("status")=="paused")title="Пауза · $title"
            }
            val notification=Notification.Builder(this@FocusService,CHANNEL).setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle(title).setContentText(detail).setStyle(Notification.BigTextStyle().bigText(detail)).setContentIntent(open(this@FocusService,"timer")).setOngoing(true).setOnlyAlertOnce(true).build()
            getSystemService(NotificationManager::class.java).notify(ONGOING,notification)
            if(++count%30==0&&!snapshot.optBoolean("local")&&active!=null)pollTimer()
            handler.postDelayed(this,1000)
        }
    }
    override fun onCreate(){super.onCreate();channels(this)}
    override fun onStartCommand(intent: Intent?,flags: Int,startId: Int): Int {
        val prefs=getSharedPreferences(PREFS,MODE_PRIVATE)
        val value=intent?.getStringExtra("snapshot")?:prefs.getString("snapshot","{}")?:"{}"
        snapshot=JSONObject(value);prefs.edit().putString("snapshot",value).apply()
        val notification=Notification.Builder(this,CHANNEL).setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle("I&W · фоновый таймер").setContentIntent(open(this,"timer")).build()
        if(Build.VERSION.SDK_INT>=34){val type=if(snapshot.optString("sound","").let{it.isNotEmpty()&&it!="null"})ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK else ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE;startForeground(ONGOING,notification,type)}else{startForeground(ONGOING,notification)}
        configureSound();schedule(this,snapshot);handler.removeCallbacks(tick);handler.post(tick)
        return START_STICKY
    }
    private fun configureSound(){
        val name=snapshot.optString("sound","")
        if(name.isEmpty()||name=="null"){player?.release();player=null;playing=null;return}
        if(name !in listOf("white","pink","brown","rain","wind","lofi"))return
        if(playing!=name){
            player?.release()
            val file=File(cacheDir,"iw-$name.wav")
            if(!file.exists())assets.open("flutter_assets/assets/audio/$name.wav").use{input->file.outputStream().use{output->input.copyTo(output)}}
            player=MediaPlayer().apply{setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build());setDataSource(file.absolutePath);isLooping=true;prepare();start()}
            playing=name
        }
        val volume=snapshot.optDouble("volume",.2).toFloat().coerceIn(0f,1f);player?.setVolume(volume,volume)
    }
    private fun pollTimer(){
        if(fetching)return
        fetching=true
        val url=snapshot.optString("serverUrl")
        network.execute{
            try{
                val connection=URL("$url/api/timer").openConnection();connection.connectTimeout=7000;connection.readTimeout=7000;connection.setRequestProperty("Origin",url)
                val text=connection.getInputStream().bufferedReader().use{it.readText()}
                val state=JSONObject(text)
                handler.post{if(snapshot.optBoolean("local")||state.optLong("revision")<snapshot.optLong("timerRevision"))return@post;snapshot.put("active",state.optJSONObject("active"));snapshot.put("timerRevision",state.optLong("revision"));if(state.has("serverNow"))snapshot.put("serverOffset",Instant.parse(state.getString("serverNow")).toEpochMilli()-System.currentTimeMillis());getSharedPreferences(PREFS,MODE_PRIVATE).edit().putString("snapshot",snapshot.toString()).apply();schedule(this,snapshot);if(snapshot.optJSONObject("active")==null&&snapshot.optString("sound","").let{it.isEmpty()||it=="null"}){stopForeground(STOP_FOREGROUND_REMOVE);stopSelf()}}
            }catch(_:Exception){}finally{fetching=false}
        }
    }
    override fun onDestroy(){handler.removeCallbacks(tick);network.shutdownNow();player?.release();super.onDestroy()}
    override fun onBind(intent:Intent?):IBinder?=null
}
