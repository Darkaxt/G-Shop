import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import org.json.JSONArray;
import org.json.JSONObject;

/** Fixed read-only patch acceptance snapshot; no credentials or catalogue export. */
public final class PatchWorkflowSnapshot {
  private static int dependencies(Object value) throws Exception {
    int count = 0;
    if (value instanceof JSONObject) {
      JSONObject object = (JSONObject) value;
      java.util.Iterator<String> keys = object.keys();
      while (keys.hasNext()) {
        String key = keys.next();
        Object child = object.get(key);
        if (key.equals("requires_patch") && child != JSONObject.NULL) count++;
        count += dependencies(child);
      }
    } else if (value instanceof JSONArray) {
      JSONArray array = (JSONArray) value;
      for (int i = 0; i < array.length(); i++) count += dependencies(array.get(i));
    }
    return count;
  }

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
              .put("steps", receipt.getJSONObject("recipe").getJSONArray("steps"))
              .put("jobRoot", receipt.getString("jobRoot"))
              .put("canonicalJobRoot", new java.io.File(receipt.getString("jobRoot")).getCanonicalPath())
              .put("inputTransfers", receipt.getJSONArray("inputTransfers").length())
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
      JSONObject cache = new JSONObject();
      int documents = 0, rootGames = 0, gameDocuments = 0, sourceDocuments = 0;
      int patchEntries = 0, prerequisites = 0;
      try (Cursor rows = db.rawQuery("SELECT document FROM drive_patch_index_cache", null)) {
        while (rows.moveToNext()) {
          JSONObject document = new JSONObject(rows.getString(0));
          documents++;
          JSONArray games = document.optJSONArray("games");
          if (games != null) rootGames += games.length();
          if (document.has("sources")) gameDocuments++;
          JSONObject sections = document.optJSONObject("sections");
          if (sections != null) {
            sourceDocuments++;
            for (String section : new String[]{"hacks", "translations"}) {
              JSONArray patches = sections.optJSONArray(section);
              if (patches != null) patchEntries += patches.length();
            }
          }
          prerequisites += dependencies(document);
        }
      }
      cache.put("documents", documents).put("rootGames", rootGames)
          .put("gameDocuments", gameDocuments).put("sourceDocuments", sourceDocuments)
          .put("patchEntries", patchEntries).put("declaredDependencies", prerequisites);
      JSONArray bindings = new JSONArray();
      try (Cursor rows = db.rawQuery("SELECT generation,COUNT(DISTINCT game_id),"
          + "COUNT(DISTINCT base_file_id) FROM drive_patch_base_links "
          + "GROUP BY scope,generation,folder_id", null)) {
        while (rows.moveToNext()) bindings.put(new JSONObject()
            .put("generation", rows.getLong(0)).put("games", rows.getInt(1))
            .put("originalFiles", rows.getInt(2)));
      }
      result.put("patchIndexCache", cache.put("bindingGroups", bindings));
      JSONArray catalogue = new JSONArray();
      try (Cursor rows = db.rawQuery("SELECT active,pending,"
          + "(SELECT COUNT(*) FROM drive_catalogue_work w WHERE w.scope=s.scope "
          + "AND w.generation=s.pending AND w.done=0),"
          + "(SELECT COUNT(*) FROM drive_catalogue_entries e WHERE e.scope=s.scope "
          + "AND e.generation=s.pending AND e.is_folder=0) "
          + "FROM drive_catalogue_state s", null)) {
        while (rows.moveToNext()) catalogue.put(new JSONObject()
            .put("activeGeneration", rows.isNull(0) ? JSONObject.NULL : rows.getLong(0))
            .put("pendingGeneration", rows.isNull(1) ? JSONObject.NULL : rows.getLong(1))
            .put("pendingFolders", rows.getInt(2)).put("pendingFilesRead", rows.getInt(3)));
      }
      result.put("catalogueRefresh", catalogue);
      System.out.println(result.toString());
    } catch (Exception error) {
      System.out.println("{\"error\":\"patch_snapshot_failed\",\"type\":\""
          + error.getClass().getSimpleName() + "\"}");
    }
  }
}
