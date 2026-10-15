package uz.iw.indicators_work

import android.content.*
import org.json.JSONObject

class ReminderReceiver:BroadcastReceiver(){
    override fun onReceive(context:Context,intent:Intent){
        val prefs=context.getSharedPreferences(FocusService.PREFS,Context.MODE_PRIVATE)
        val snapshot=JSONObject(prefs.getString("snapshot","{}")?:"{}")
        if(intent.getStringExtra("kind")=="timer"){
            val active=snapshot.optJSONObject("active")?:return
            val key=active.optString("id")+":"+active.optLong("plannedMs")
            if(!FocusService.appVisible&&prefs.getString("alerted","")!=key){prefs.edit().putString("alerted",key).apply();FocusService.alert(context,true)}
        }else if(intent.getStringExtra("kind")=="leisure"){
            FocusService.alertLeisure(context,snapshot)
        }else if(intent.action==Intent.ACTION_BOOT_COMPLETED){FocusService.schedule(context,snapshot);return}
        else{
            FocusService.alert(context,false)
            val hidden=snapshot.optJSONObject("hidden")?:JSONObject()
            val norms=snapshot.optJSONArray("norms")
            val now=System.currentTimeMillis()
            prefs.edit().putLong("pomodoroReminder:${FocusService.date(now)}",now+3600000).apply()
            if(norms!=null)for(i in 0 until norms.length()){val norm=norms.getJSONObject(i);hidden.put(FocusService.date(now)+":"+norm.optString("workRef"),now+1000)}
            snapshot.put("hidden",hidden);prefs.edit().putString("snapshot",snapshot.toString()).apply()
        }
        FocusService.schedule(context,snapshot)
    }
}
