package uz.shs.better_player_plus

import android.content.Context
import androidx.mediarouter.app.MediaRouteButton
import com.google.android.gms.cast.framework.CastButtonFactory
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

internal class BetterPlayerCastButtonFactory(
    private val castManager: BetterPlayerCastManager
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val parameters = args as? Map<*, *>
        val textureId = (parameters?.get("textureId") as? Number)?.toLong()
        if (textureId != null) castManager.setTarget(textureId)
        val button = MediaRouteButton(context).apply {
            contentDescription = "Cast"
            CastButtonFactory.setUpMediaRouteButton(context.applicationContext, this)
        }
        return object : PlatformView {
            override fun getView() = button
            override fun dispose() = Unit
        }
    }
}
