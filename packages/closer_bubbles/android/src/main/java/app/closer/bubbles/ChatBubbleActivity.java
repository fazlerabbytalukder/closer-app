package app.closer.bubbles;

import androidx.annotation.Nullable;

import java.util.Collections;
import java.util.List;

import io.flutter.embedding.android.FlutterActivity;

/**
 * What opens inside the chat head. Runs the app's `main(["bubble"])`, which
 * shows only the chat. Declared in the app's AndroidManifest (embedded,
 * resizeable, documentLaunchMode="always", as bubbles require).
 */
public class ChatBubbleActivity extends FlutterActivity {
    @Nullable
    @Override
    public List<String> getDartEntrypointArgs() {
        return Collections.singletonList("bubble");
    }

    @Override
    public boolean shouldHandleDeeplinking() {
        return false;
    }
}
