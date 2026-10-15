package uz.iw.indicators_work

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri

/** Only bundled, public sounds; no user files or arbitrary paths. */
object TimerRingtones {
    val names=linkedMapOf("bip_bip" to "Бип-бип","sonar" to "Сонар","glass" to "Стекло","marimba" to "Маримба","orbit" to "Орбита","warm_bell" to "Тёплый колокол","classic" to "Прежний сигнал")
    fun valid(id:String?)=if(names.containsKey(id))id!! else "bip_bip"
    fun channel(context:Context,requested:String?):String {
        val id=valid(requested)
        val channelId="iw_timer_ringtone_${id}_v1"
        val manager=context.getSystemService(NotificationManager::class.java)
        if(manager.getNotificationChannel(channelId)==null) {
            val channel=NotificationChannel(channelId,"Таймер · ${names[id]}",NotificationManager.IMPORTANCE_HIGH)
            channel.description="Окончание помидорки, перерыва и Leisure"
            channel.setSound(Uri.parse("content://${context.packageName}.ringtones/$id.wav"),AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            manager.createNotificationChannel(channel)
        }
        return channelId
    }
}
