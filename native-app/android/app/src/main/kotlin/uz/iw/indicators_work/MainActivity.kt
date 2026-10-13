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
    override fun configureFlutterEngine(engine:FlutterEngine){
        super.configureFlutterEngine(engine)
        FocusService.channels(this)
        bridge=MethodChannel(engine.dartExecutor.binaryMessenger,"iw/background")
        bridge!!.setMethodCallHandler{call,result->
            try{
                when(call.method){
                    "update"->{
                        val payload=JSONObject(call.arguments as Map<*,*>)
                        getSharedPreferences(FocusService.PREFS,MODE_PRIVATE).edit().putString("snapshot",payload.toString()).apply()
                        FocusService.schedule(this,payload)
                        val sound=payload.optString("sound","")
                        if(payload.optJSONObject("active")!=null||(sound.isNotEmpty()&&sound!="null")){
                            val service=Intent(this,FocusService::class.java).putExtra("snapshot",payload.toString())
                            if(Build.VERSION.SDK_INT>=26)startForegroundService(service)else startService(service)
                        }else{stopService(Intent(this,FocusService::class.java))}
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
    override fun onNewIntent(intent:Intent){super.onNewIntent(intent);setIntent(intent);bridge?.invokeMethod("open",intent.getStringExtra("iw_screen"));intent.removeExtra("iw_screen")}
}
