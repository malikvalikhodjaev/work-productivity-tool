package uz.iw.indicators_work

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/** Stable URIs for channels. Read-only allowlist of seven public assets. */
class TimerRingtoneProvider:ContentProvider() {
    override fun onCreate()=true
    private fun id(uri:Uri):String {
        val parts=uri.pathSegments
        if(uri.authority!="${context!!.packageName}.ringtones"||parts.size!=1||!parts[0].endsWith(".wav"))throw FileNotFoundException("Unknown ringtone")
        val id=parts[0].removeSuffix(".wav")
        if(!TimerRingtones.names.containsKey(id))throw FileNotFoundException("Unknown ringtone")
        return id
    }
    @Synchronized private fun file(uri:Uri):File {
        val id=id(uri)
        val directory=File(context!!.filesDir,"timer-ringtones-v1").apply{mkdirs()}
        val file=File(directory,"$id.wav")
        if(!file.exists()) {
            val asset=if(id=="classic")"flutter_assets/assets/audio/alarm.wav"else"flutter_assets/assets/audio/ringtones/$id.wav"
            val temporary=File(directory,"$id.wav.tmp")
            context!!.assets.open(asset).use{input->temporary.outputStream().use{output->input.copyTo(output)}}
            if(!temporary.renameTo(file)){temporary.delete();throw FileNotFoundException("Cannot prepare ringtone")}
        }
        return file
    }
    override fun openFile(uri:Uri,mode:String):ParcelFileDescriptor {
        if(mode!="r")throw FileNotFoundException("Read-only ringtone")
        return ParcelFileDescriptor.open(file(uri),ParcelFileDescriptor.MODE_READ_ONLY)
    }
    override fun getType(uri:Uri):String {id(uri);return "audio/wav"}
    override fun query(uri:Uri,projection:Array<out String>?,selection:String?,selectionArgs:Array<out String>?,sortOrder:String?):Cursor {
        val file=file(uri)
        val columns=projection?:arrayOf(OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE)
        return MatrixCursor(columns).apply{addRow(columns.map{when(it){OpenableColumns.DISPLAY_NAME->file.name;OpenableColumns.SIZE->file.length();else->null}})}
    }
    override fun insert(uri:Uri,values:ContentValues?):Uri?=throw UnsupportedOperationException("Read-only ringtone")
    override fun update(uri:Uri,values:ContentValues?,selection:String?,selectionArgs:Array<out String>?):Int=throw UnsupportedOperationException("Read-only ringtone")
    override fun delete(uri:Uri,selection:String?,selectionArgs:Array<out String>?):Int=throw UnsupportedOperationException("Read-only ringtone")
}
