import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import org.json.JSONArray;
import org.json.JSONObject;

/** Fixed read-only patch acceptance snapshot; no credentials or catalogue export. */
public final class PatchWorkflowSnapshot {
  public static void main(String[] args) {
    if (args.length != 1 || !args[0].matches("[a-z0-9_-]{1,64}")) throw new IllegalArgumentException();
    try (SQLiteDatabase db = SQLiteDatabase.openDatabase(
        "/data/user/0/com.darkaxt.rshop/databases/rshop.db", null,
        SQLiteDatabase.OPEN_READONLY | SQLiteDatabase.NO_LOCALIZED_COLLATORS)) {
      JSONObject result = new JSONObject().put("readOnly", true).put("schema", db.getVersion());
      JSONArray builds = new JSONArray();
      try (Cursor rows = db.rawQuery("SELECT state,record_json FROM patch_builds "
          + "WHERE platform_id=? ORDER BY created_at DESC LIMIT 12", new String[]{args[0]})) {
        while (rows.moveToNext()) {
          JSONObject receipt = new JSONObject(rows.getString(1));
          JSONObject build = new JSONObject().put("state", rows.getString(0))
              .put("buildId", receipt.getString("buildId"))
              .put("title", receipt.getString("title"))
              .put("cleanup", receipt.optString("scratchCleanup"))
              .put("issue", receipt.optString("issue"));
          JSONObject output = receipt.optJSONObject("outputArtifact");
          if (output != null) build.put("outputSize", output.optLong("sizeBytes"))
              .put("outputChecksums", output.optJSONObject("providerChecksums"));
          String transfer = receipt.optString("transferId");
          if (!transfer.isEmpty()) {
            try (Cursor installed = db.rawQuery("SELECT record_json FROM installed_artifacts WHERE transfer_id=?",
                new String[]{transfer})) {
              if (installed.moveToFirst()) {
                JSONObject value = new JSONObject(installed.getString(0));
                build.put("installedRoot", value.getString("destinationRoot"))
                    .put("installedFile", value.getString("relativePath"))
                    .put("verifiedChecksums", value.getJSONObject("verifiedChecksums"));
              }
            }
          }
          builds.put(build);
        }
      }
      result.put("builds", builds);
      System.out.println(result.toString());
    } catch (Exception error) {
      System.out.println("{\"error\":\"patch_snapshot_failed\",\"type\":\""
          + error.getClass().getSimpleName() + "\"}");
    }
  }
}
