import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import org.json.JSONObject;

/** Fixed read-only aggregate observation; no credentials, titles or media URLs. */
public final class RShopS25ResourceAudit {
  public static void main(String[] args) throws Exception {
    if (args.length != 0) throw new IllegalArgumentException("No query arguments");
    SQLiteDatabase db = SQLiteDatabase.openDatabase(
        "/data/user/0/com.darkaxt.rshop/databases/rshop.db", null,
        SQLiteDatabase.OPEN_READONLY | SQLiteDatabase.NO_LOCALIZED_COLLATORS);
    try {
      long job;
      JSONObject report = new JSONObject();
      try (Cursor rows = db.rawQuery("SELECT id,state,selection_json FROM metadata_refresh_jobs "
          + "WHERE is_artwork=1 AND resources_only=1 ORDER BY id DESC LIMIT 1", null)) {
        if (!rows.moveToFirst()) throw new IllegalStateException("No resource job");
        job = rows.getLong(0);
        report.put("job", job).put("state", rows.getString(1));
        if (!rows.isNull(2)) report.put("selection", new JSONObject(rows.getString(2)));
      }
      JSONObject counts = new JSONObject();
      int total = 0;
      try (Cursor rows = db.rawQuery("SELECT status,media_json FROM metadata_artwork_items "
          + "WHERE job_id=? LIMIT 4097", new String[] {Long.toString(job)})) {
        while (rows.moveToNext()) {
          if (++total > 4096) throw new IllegalStateException("Scope exceeds observation budget");
          JSONObject media = new JSONObject(rows.getString(1));
          String key = media.getString("type") + ":" + rows.getString(0);
          counts.put(key, counts.optInt(key) + 1);
        }
      }
      report.put("items", total).put("resources", counts);
      try (Cursor rows = db.rawQuery("SELECT requests_per_minute,max_threads,"
          + "remaining_requests,quota_exhausted FROM metadata_provider_limits "
          + "WHERE provider_id='screenscraper'", null)) {
        if (rows.moveToFirst()) {
          JSONObject budget = new JSONObject();
          for (int column = 0; column < rows.getColumnCount(); column++) {
            budget.put(rows.getColumnName(column),
                rows.isNull(column) ? JSONObject.NULL : rows.getLong(column));
          }
          report.put("providerBudget", budget);
        }
      }
      int games = 0;
      JSONObject imported = new JSONObject();
      try (Cursor rows = db.rawQuery("SELECT record_json FROM library_metadata "
          + "WHERE provider_id='packaging' LIMIT 4097", null)) {
        int observed = 0;
        while (rows.moveToNext()) {
          if (++observed > 4096) throw new IllegalStateException("Too many packaging records");
          JSONObject record = new JSONObject(rows.getString(0));
          if (!"gba".equals(record.getString("platformId"))) continue;
          games++;
          org.json.JSONArray media = record.getJSONArray("media");
          for (int index = 0; index < media.length(); index++) {
            String role = media.getJSONObject(index).getString("type");
            imported.put(role, imported.optInt(role) + 1);
          }
        }
      }
      report.put("packagingGames", games).put("packagingResources", imported);
      System.out.println(report.toString());
    } finally { db.close(); }
  }
}
