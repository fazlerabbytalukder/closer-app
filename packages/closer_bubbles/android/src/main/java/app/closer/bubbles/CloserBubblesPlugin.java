package app.closer.bubbles;

import android.content.Context;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Method channel "closer_bubbles" (see lib/closer_bubbles.dart). */
public class CloserBubblesPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private Context context;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "closer_bubbles");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
        context = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "isSupported":
                    result.success(Bubbles.isSupported());
                    break;
                case "areAllowed":
                    result.success(Bubbles.areAllowed(context));
                    break;
                case "openSettings":
                    Bubbles.openSettings(context);
                    result.success(null);
                    break;
                case "show": {
                    if (!Bubbles.isSupported()) {
                        result.success(false);
                        break;
                    }
                    String name = call.argument("name");
                    Boolean expand = call.argument("expand");
                    Boolean silent = call.argument("silent");
                    result.success(Bubbles.show(
                            context,
                            name == null ? "" : name,
                            call.argument("avatarPath"),
                            call.argument("message"),
                            call.argument("messageId"),
                            expand != null && expand,
                            silent != null && silent));
                    break;
                }
                case "dismiss":
                    Bubbles.dismiss(context);
                    result.success(null);
                    break;
                default:
                    result.notImplemented();
            }
        } catch (Exception e) {
            result.error("bubbles", e.getMessage(), null);
        }
    }
}
