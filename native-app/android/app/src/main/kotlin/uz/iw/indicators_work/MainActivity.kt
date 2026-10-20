package uz.iw.indicators_work

import android.Manifest
import android.app.AlarmManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import androidx.core.content.FileProvider

class MainActivity:FlutterActivity(){
    private var bridge:MethodChannel?=null
    private var backupPicker:MethodChannel.Result?=null
    private fun updateBackground(payload:JSONObject){
        val saved=getSharedPreferences(FocusService.PREFS,MODE_PRIVATE).getString("snapshot",null)?.let{JSONObject(it)}
        if(saved!=null&&!payload.optBoolean("timerOnly")&&!payload.optBoolean("local")&&!saved.optBoolean("local")&&
            saved.optString("serverUrl")==payload.optString("serverUrl")&&saved.optLong("timerRevision")>payload.optLong("timerRevision")){
            payload.put("active",saved.optJSONObject("active"))
            payload.put("timerRevision",saved.optLong("timerRevision"))
            payload.put("serverOffset",saved.optLong("serverOffset"))
        }
        getSharedPreferences(FocusService.PREFS,MODE_PRIVATE).edit().putString("snapshot",payload.toString()).apply()
        FocusService.schedule(this,payload)
        val sound=payload.optString("sound","")
        if(payload.optJSONObject("active")!=null||(sound.isNotEmpty()&&sound!="null")){
            if(FocusService.appVisible||FocusService.running){
                val service=Intent(this,FocusService::class.java).putExtra("snapshot",payload.toString())
                startForegroundService(service)
            }
        }else{stopService(Intent(this,FocusService::class.java))}
    }
    override fun onStart(){
        super.onStart();FocusService.appVisible=true
        val prefs=getSharedPreferences(FocusService.PREFS,MODE_PRIVATE)
        prefs.edit().remove("overlayDismissedSession").apply()
        val snapshot=prefs.getString("snapshot",null)
        if(snapshot!=null)updateBackground(JSONObject(snapshot))
    }
    override fun onStop(){FocusService.appVisible=false;super.onStop()}
    override fun configureFlutterEngine(engine:FlutterEngine){
        super.configureFlutterEngine(engine)
        FocusService.channels(this)
        bridge=MethodChannel(engine.dartExecutor.binaryMessenger,"iw/background")
        bridge!!.setMethodCallHandler{call,result->
            try{
                when(call.method){
                    "pickBackup"->{
                        if(backupPicker!=null){result.error("busy","File selection is already open",null)}else{
                            backupPicker=result
                            val picker=Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("application/json")
                            try{startActivityForResult(picker,17041)}catch(error:Exception){backupPicker=null;result.error("picker",error.message,null)}
                        }
                    }
                    "update"->{
                        val payload=JSONObject(call.arguments as Map<*,*>)
                        updateBackground(payload)
                        result.success(true)
                    }
                    "overlayAllowed"->{result.success(Settings.canDrawOverlays(this))}
                    "ringtoneSettings"->{
                        val channelId=TimerRingtones.channel(this,call.arguments as? String)
                        startActivity(Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,packageName).putExtra(Settings.EXTRA_CHANNEL_ID,channelId))
                        result.success(true)
                    }
                    "claimTimerSound"->{
                        val arguments=call.arguments as Map<*,*>
                        val name=if(arguments["kind"]=="leisure")"leisureAlerted"else"alerted"
                        val key=arguments["key"] as String
                        require(key.isNotEmpty()&&key.length<=200)
                        val prefs=getSharedPreferences(FocusService.PREFS,MODE_PRIVATE)
                        val fresh=prefs.getString(name,null)!=key
                        if(fresh)prefs.edit().putString(name,key).apply()
                        result.success(fresh)
                    }
                    "overlayPermission"->{
                        val settings=Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,Uri.parse("package:$packageName"))
                        if(settings.resolveActivity(packageManager)!=null)startActivity(settings)
                        else startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
                        result.success(true)
                    }
                    "shareExport"->{
                        val arguments=call.arguments as Map<*,*>
                        val file=File(arguments["path"] as String).canonicalFile
                        val directory=File(filesDir,"exports").canonicalFile
                        require(file.path.startsWith(directory.path+File.separator)&&file.isFile&&file.extension=="json") { "Only application exports can be shared" }
                        val uri=FileProvider.getUriForFile(this,"$packageName.exports",file)
                        val share=Intent(Intent.ACTION_SEND).setType("application/json").putExtra(Intent.EXTRA_STREAM,uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        startActivity(Intent.createChooser(share,"Сохранить локальную копию"))
                        result.success(true)
                    }
                    "exactAlarmAllowed"->{result.success(Build.VERSION.SDK_INT<31||getSystemService(AlarmManager::class.java).canScheduleExactAlarms())}
                    "permissions"->{
                        if(Build.VERSION.SDK_INT>=33&&checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED){requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS),701)}
                        else if(Build.VERSION.SDK_INT>=31&&!getSystemService(AlarmManager::class.java).canScheduleExactAlarms()){startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,Uri.parse("package:$packageName")))}
                        result.success(true)
                    }
                    "launchScreen"->{result.success(intent.getStringExtra("iw_screen"));intent.removeExtra("iw_screen")}
                    else->result.notImplemented()
                }
            }catch(error:Exception){result.error("iw_background",error.message,null)}
        }
    }
    override fun onActivityResult(requestCode:Int,resultCode:Int,data:Intent?){
        super.onActivityResult(requestCode,resultCode,data)
        if(requestCode!=17041)return
        val reply=backupPicker?:return
        backupPicker=null
        if(resultCode!=RESULT_OK||data?.data==null){reply.success(null);return}
        try{
            val output=java.io.ByteArrayOutputStream()
            contentResolver.openInputStream(data.data!!)?.use { input ->
                val buffer=ByteArray(8192)
                while(true){val count=input.read(buffer);if(count<0)break;require(output.size()+count<=8*1024*1024){"Backup exceeds 8 MiB"};output.write(buffer,0,count)}
            }?:throw IllegalArgumentException("Cannot read backup")
            reply.success(output.toString("UTF-8"))
        }catch(error:Exception){reply.error("backup",error.message,null)}
    }
    override fun onNewIntent(intent:Intent){super.onNewIntent(intent);setIntent(intent);bridge?.invokeMethod("open",intent.getStringExtra("iw_screen"));intent.removeExtra("iw_screen")}
}
