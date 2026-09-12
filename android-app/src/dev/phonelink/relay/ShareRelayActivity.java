package dev.phonelink.relay;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Log;
import android.widget.Toast;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Share-sheet target. Anything shared from a phone app lands in
 * /sdcard/PhoneLink/ via direct file write (needs MANAGE_EXTERNAL_STORAGE —
 * granted once, see init.sh), where the PhoneLink backend picks it up over
 * adb. A visible top-level folder, not buried in Download.
 */
public class ShareRelayActivity extends Activity {
    static final String TAG = "RELAY";
    static final File INBOX = new File(Environment.getExternalStorageDirectory(), "PhoneLink");

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        try {
            Intent i = getIntent();
            if (Intent.ACTION_SEND.equals(i.getAction())) handleSend(i);
        } catch (Exception e) {
            Log.e(TAG, "share failed", e);
            Toast.makeText(this, "Share failed: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
        finish();
    }

    private void handleSend(Intent i) throws Exception {
        if (!Environment.isExternalStorageManager())
            throw new SecurityException("allow 'All files access' for PhoneRelay (Settings, once)");
        if (!INBOX.isDirectory() && !INBOX.mkdirs())
            throw new java.io.IOException("cannot create " + INBOX);
        ContentResolver cr = getContentResolver();
        Uri stream = i.getParcelableExtra(Intent.EXTRA_STREAM);
        String ts = String.valueOf(System.currentTimeMillis());
        if (stream != null) {
            String name = "phonelink-" + ts + "-" + fileNameOf(cr, stream);
            try (InputStream in = cr.openInputStream(stream);
                 OutputStream os = new FileOutputStream(new File(INBOX, name))) {
                byte[] buf = new byte[65536];
                int n;
                while ((n = in.read(buf)) > 0) os.write(buf, 0, n);
            }
            Log.d(TAG, "file share landed: " + name);
            Toast.makeText(this, "Saved to PhoneLink/", Toast.LENGTH_LONG).show();
        } else {
            String subj = i.getStringExtra(Intent.EXTRA_SUBJECT);
            String text = i.getStringExtra(Intent.EXTRA_TEXT);
            String body = "";
            if (text != null) body += text;
            if (subj != null) body = body + (body.length() > 0 ? "\n\n" : "") + subj;
            if (body.trim().length() == 0) body = "(empty share)";
            String name = "phonelink-" + ts + ".txt";
            try (OutputStream os = new FileOutputStream(new File(INBOX, name))) {
                os.write(body.getBytes("UTF-8"));
            }
            Log.d(TAG, "text share landed: " + body.length() + " chars");
            Toast.makeText(this, "Saved to PhoneLink/", Toast.LENGTH_LONG).show();
        }
    }

    private static String fileNameOf(ContentResolver cr, Uri uri) {
        try (Cursor c = cr.query(uri, new String[]{MediaStore.MediaColumns.DISPLAY_NAME}, null, null, null)) {
            if (c != null && c.moveToFirst()) {
                String n = c.getString(0);
                if (n != null && n.length() > 0) return sanitize(n);
            }
        } catch (Exception ignored) {}
        String p = uri.getLastPathSegment();
        return p != null ? sanitize(p) : "file";
    }

    private static String sanitize(String n) {
        String s = n.replaceAll("[^A-Za-z0-9._-]", "_");
        return s.length() > 0 ? s : "file";
    }
}
