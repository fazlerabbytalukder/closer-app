package app.closer.bubbles;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.service.notification.StatusBarNotification;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.app.Person;
import androidx.core.content.LocusIdCompat;
import androidx.core.content.pm.ShortcutInfoCompat;
import androidx.core.content.pm.ShortcutManagerCompat;
import androidx.core.graphics.drawable.IconCompat;

import java.io.File;
import java.util.Collections;

/**
 * Chat heads for Duosy, built on Android's conversation bubbles (Android 11+).
 *
 * One conversation (the partner), one notification slot (id 1007, the same id
 * the Dart side uses for chat notifications, so they replace each other).
 * Tapping the bubble opens {@link ChatBubbleActivity}, which runs the chat UI.
 */
final class Bubbles {
    private Bubbles() {}

    static final String CHANNEL = "chat";
    static final String SHORTCUT = "partner_chat";
    static final int NOTIFICATION_ID = 1007;
    private static final String PREFS = "closer_bubbles";
    private static final String LAST_ID = "last_message_id";

    static boolean isSupported() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.R;
    }

    /** Whether the system will actually show our conversation as a bubble. */
    static boolean areAllowed(Context c) {
        if (!isSupported()) return false;
        NotificationManager nm = c.getSystemService(NotificationManager.class);
        if (nm == null || !nm.areNotificationsEnabled()) return false;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            int pref = nm.getBubblePreference();
            if (pref == NotificationManager.BUBBLE_PREFERENCE_NONE) return false;
            if (pref == NotificationManager.BUBBLE_PREFERENCE_ALL) return true;
        } else {
            //noinspection deprecation
            if (!nm.areBubblesAllowed()) return false;
        }
        // "Selected conversations": only if the user bubbled this one.
        NotificationChannel conversation = nm.getNotificationChannel(CHANNEL, SHORTCUT);
        if (conversation != null) return conversation.canBubble();
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S;
    }

    static void openSettings(Context c) {
        Intent i = isSupported()
                ? new Intent(Settings.ACTION_APP_NOTIFICATION_BUBBLE_SETTINGS)
                : new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS);
        i.putExtra(Settings.EXTRA_APP_PACKAGE, c.getPackageName());
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        c.startActivity(i);
    }

    /**
     * Posts (or updates) the partner's conversation notification with a bubble.
     *
     * @param messageId used to skip duplicates (push + live listener).
     * @param message   the partner's message, or null for "pop out" (no new message).
     * @param expand    open the bubble right away (only while the app is in front).
     * @return false if this message was already shown or notifications are blocked.
     */
    static boolean show(Context c, String name, @Nullable String avatarPath, @Nullable String message,
                        @Nullable String messageId, boolean expand, boolean silent) {
        SharedPreferences prefs = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        if (messageId != null && messageId.equals(prefs.getString(LAST_ID, null))) return false;
        if (messageId != null) prefs.edit().putString(LAST_ID, messageId).apply();

        NotificationManager nm = c.getSystemService(NotificationManager.class);
        ensureChannel(nm);

        IconCompat icon = IconCompat.createWithAdaptiveBitmap(avatar(avatarPath, name));
        Person partner = new Person.Builder().setName(name).setKey("partner").setIcon(icon).setImportant(true).build();
        Person me = new Person.Builder().setName("You").setKey("me").build();

        Intent open = new Intent(Intent.ACTION_VIEW, Uri.parse("closer://chat"))
                .setPackage(c.getPackageName())
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        LocusIdCompat locus = new LocusIdCompat(SHORTCUT);
        ShortcutInfoCompat shortcut = new ShortcutInfoCompat.Builder(c, SHORTCUT)
                .setLongLived(true)
                .setShortLabel(name)
                .setIcon(icon)
                .setPerson(partner)
                .setIntent(open)
                .setLocusId(locus)
                .setCategories(Collections.singleton("app.closer.category.CHAT"))
                .build();
        ShortcutManagerCompat.pushDynamicShortcut(c, shortcut);

        int mutable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ? PendingIntent.FLAG_MUTABLE : 0;
        Intent bubble = new Intent(c, ChatBubbleActivity.class)
                .setAction(Intent.ACTION_VIEW)
                .setData(Uri.parse("closer://chat/bubble"));
        PendingIntent bubbleIntent = PendingIntent.getActivity(c, 1, bubble, PendingIntent.FLAG_UPDATE_CURRENT | mutable);
        PendingIntent contentIntent = PendingIntent.getActivity(c, 2, open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

        NotificationCompat.BubbleMetadata meta = new NotificationCompat.BubbleMetadata.Builder(bubbleIntent, icon)
                .setDesiredHeight(640)
                .setAutoExpandBubble(expand)
                .setSuppressNotification(expand)
                .build();

        // Keep the earlier messages of the current notification.
        NotificationCompat.MessagingStyle style = null;
        if (nm != null) {
            for (StatusBarNotification sbn : nm.getActiveNotifications()) {
                if (sbn.getId() == NOTIFICATION_ID && sbn.getTag() == null) {
                    style = NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(sbn.getNotification());
                }
            }
        }
        if (style == null) style = new NotificationCompat.MessagingStyle(me);
        if (message != null && !message.isEmpty()) {
            style.addMessage(message, System.currentTimeMillis(), partner);
        } else if (style.getMessages().isEmpty()) {
            style.addMessage("Tap to chat 💬", System.currentTimeMillis(), (Person) null);
        }

        String text = message != null && !message.isEmpty() ? message : "Tap to chat 💬";
        NotificationCompat.Builder b = new NotificationCompat.Builder(c, CHANNEL)
                .setSmallIcon(smallIcon(c))
                .setContentTitle(name)
                .setContentText(text)
                .setStyle(style)
                .setShortcutId(SHORTCUT)
                .setLocusId(locus)
                .setBubbleMetadata(meta)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(contentIntent)
                .setAutoCancel(true)
                .addPerson(partner)
                .setSilent(silent || message == null)
                .setOnlyAlertOnce(message == null);
        try {
            NotificationManagerCompat.from(c).notify(NOTIFICATION_ID, b.build());
            return true;
        } catch (SecurityException e) {
            // POST_NOTIFICATIONS not granted.
            return false;
        }
    }

    /** Removes the bubble, its notification and the conversation shortcut. */
    static void dismiss(Context c) {
        NotificationManagerCompat.from(c).cancel(NOTIFICATION_ID);
        ShortcutManagerCompat.removeLongLivedShortcuts(c, Collections.singletonList(SHORTCUT));
        c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(LAST_ID).apply();
    }

    private static void ensureChannel(@Nullable NotificationManager nm) {
        if (nm == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        if (nm.getNotificationChannel(CHANNEL) != null) return;
        NotificationChannel ch = new NotificationChannel(CHANNEL, "Chat & goodnights", NotificationManager.IMPORTANCE_HIGH);
        nm.createNotificationChannel(ch);
    }

    private static int smallIcon(Context c) {
        int id = c.getResources().getIdentifier("ic_stat_closer", "drawable", c.getPackageName());
        return id != 0 ? id : c.getApplicationInfo().icon;
    }

    /** 216px adaptive-icon bitmap: the partner's photo, or their initial on pink. */
    private static Bitmap avatar(@Nullable String path, String name) {
        final int size = 216;
        Bitmap out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(out);
        Bitmap photo = null;
        if (path != null && new File(path).exists()) {
            BitmapFactory.Options o = new BitmapFactory.Options();
            o.inSampleSize = 2;
            photo = BitmapFactory.decodeFile(path, o);
        }
        if (photo != null) {
            int side = Math.min(photo.getWidth(), photo.getHeight());
            int left = (photo.getWidth() - side) / 2;
            int top = (photo.getHeight() - side) / 2;
            Paint p = new Paint(Paint.FILTER_BITMAP_FLAG | Paint.ANTI_ALIAS_FLAG);
            canvas.drawBitmap(photo, new Rect(left, top, left + side, top + side), new Rect(0, 0, size, size), p);
            photo.recycle();
        } else {
            canvas.drawColor(Color.parseColor("#FF5C8A"));
            Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
            p.setColor(Color.WHITE);
            p.setTextSize(size * 0.36f);
            p.setTypeface(Typeface.create(Typeface.DEFAULT, Typeface.BOLD));
            p.setTextAlign(Paint.Align.CENTER);
            String initial = name.isEmpty() ? "♥" : name.substring(0, name.offsetByCodePoints(0, 1)).toUpperCase();
            Paint.FontMetrics fm = p.getFontMetrics();
            canvas.drawText(initial, size / 2f, size / 2f - (fm.ascent + fm.descent) / 2f, p);
        }
        return out;
    }
}
