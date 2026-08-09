package uz.shs.better_player_plus

import android.content.Context
import android.content.pm.PackageManager
import com.google.android.gms.cast.CastMediaControlIntent
import com.google.android.gms.cast.framework.CastOptions
import com.google.android.gms.cast.framework.OptionsProvider
import com.google.android.gms.cast.framework.SessionProvider

class BetterPlayerCastOptionsProvider : OptionsProvider {
    override fun getCastOptions(context: Context): CastOptions {
        val metadata = context.packageManager.getApplicationInfo(
            context.packageName,
            PackageManager.GET_META_DATA
        ).metaData
        val receiverApplicationId = metadata
            ?.getString(RECEIVER_APPLICATION_ID_META_DATA)
            ?.takeIf { it.isNotBlank() }
            ?: CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID
        return CastOptions.Builder()
            .setReceiverApplicationId(receiverApplicationId)
            .build()
    }

    override fun getAdditionalSessionProviders(context: Context): List<SessionProvider>? = null

    companion object {
        const val RECEIVER_APPLICATION_ID_META_DATA =
            "uz.shs.better_player_plus.CAST_RECEIVER_APPLICATION_ID"
    }
}
