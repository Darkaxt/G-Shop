import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import java.nio.charset.StandardCharsets;
import org.json.JSONArray;
import org.json.JSONObject;

/** Private, fixed READONLY S7 retention observation, not a migration executor.
 * This reads the normal app's projection; unlike retentionPage it cannot refresh
 * it. Dirty/missing bindings prevent usable exact-member planning. Incomplete
 * rating coverage stays visible but is not a veto under specification revision 19.
 * This observation never authorizes removal.
 * Source equality with the actual Dart query is checked in the focused tests.
 */
public final class RShopRetentionSnapshot {
  static final String SQL = """
WITH scoped AS (
        SELECT * FROM library_query_editions WHERE member = 1 AND platform_id = ?),
        priorities AS (SELECT group_key, MIN(source_order) AS source_order
          FROM scoped WHERE rating_eligible = 1 GROUP BY group_key),
        scores AS (SELECT s.group_key, p.source_order, MIN(s.score) AS score
          FROM scoped s JOIN priorities p ON p.group_key = s.group_key
          AND p.source_order = s.source_order
          WHERE s.rating_eligible = 1 GROUP BY s.group_key, p.source_order
          HAVING MIN(s.score) = MAX(s.score)),
        ranks AS (SELECT group_key, source_order, score,
          ROW_NUMBER() OVER (ORDER BY score DESC, group_key) AS rank FROM scores), summary AS (SELECT
          (SELECT COUNT(DISTINCT group_key) FROM scoped) AS collection_games,
          (SELECT COUNT(*) FROM ranks) AS ranked_games,
          (SELECT COUNT(*) FROM scoped) AS total_members,
          (SELECT COUNT(*) FROM games g WHERE g.systemSlug = ? AND g.is_folder = 0
            AND NOT EXISTS (SELECT 1 FROM scoped s WHERE s.cache_row_id = g.id))
            AS unbound_artifacts),
          page_rows AS (SELECT s.edition_id, s.game_id, s.group_key,
            s.cache_row_id, r.rank AS canonical_rank FROM scoped s
            LEFT JOIN ranks r ON r.group_key = s.group_key
            ORDER BY r.rank IS NULL, r.rank, s.group_key, s.edition_id
            LIMIT ? OFFSET ?)
          SELECT page_rows.*, summary.* FROM summary
          LEFT JOIN page_rows ON 1 = 1
          ORDER BY canonical_rank IS NULL, canonical_rank, group_key, edition_id
      """;

  public static void main(String[] args) {
    try {
      if (args.length != 2 || !args[0].matches("[a-z0-9][a-z0-9_-]{0,63}")
          || !args[1].matches("0|[1-9][0-9]{0,6}")) {
        throw new IllegalArgumentException("Exact platform and bounded offset required");
      }
      int offset = Integer.parseInt(args[1]);
      if (offset > 100000) throw new IllegalArgumentException("Catalogue bound");
      String query = "SELECT q.*,g.artifact_key,"
          + "(SELECT COUNT(*) FROM library_query_dirty) AS dirty_editions,"
          + "(SELECT COUNT(*) FROM library_query_cache_dirty) AS dirty_artifacts FROM ("
          + SQL + ") q LEFT JOIN games g ON g.id=q.cache_row_id "
          + "ORDER BY canonical_rank IS NULL,canonical_rank,group_key,edition_id";
      try (SQLiteDatabase db = SQLiteDatabase.openDatabase("databases/rshop.db", null,
          SQLiteDatabase.OPEN_READONLY | SQLiteDatabase.NO_LOCALIZED_COLLATORS);
           Cursor rows = db.rawQuery(query, new String[]{args[0],args[0],"128",args[1]})) {
        if (!db.isReadOnly() || !rows.moveToFirst()) {
          throw new IllegalStateException("Read-only summary required");
        }
        JSONObject result = new JSONObject().put("schema","rshop.s7.retention.v2")
            .put("platform",args[0]).put("offset",offset).put("readOnly",true);
        for (String field : new String[]{"collection_games","ranked_games","total_members",
            "unbound_artifacts","dirty_editions","dirty_artifacts"}) {
          result.put(field,rows.getLong(rows.getColumnIndexOrThrow(field)));
        }
        JSONArray members = new JSONArray();
        do {
          if (rows.isNull(rows.getColumnIndexOrThrow("edition_id"))) continue;
          if (members.length() >= 128) throw new IllegalStateException("Page bound");
          JSONObject member = new JSONObject();
          for (String field : new String[]{"edition_id","game_id","group_key"}) {
            String value=rows.getString(rows.getColumnIndexOrThrow(field));
            if (value==null || value.getBytes(StandardCharsets.UTF_8).length>4096) {
              throw new IllegalStateException("Identity bound");
            }
            member.put(field,value);
          }
          member.put("cache_row_id",rows.getLong(rows.getColumnIndexOrThrow("cache_row_id")));
          int artifactKey=rows.getColumnIndexOrThrow("artifact_key");
          String key=rows.isNull(artifactKey)?null:rows.getString(artifactKey);
          if (key!=null && key.getBytes(StandardCharsets.UTF_8).length>4096) {
            throw new IllegalStateException("Artifact identity bound");
          }
          member.put("artifact_key",key==null?JSONObject.NULL:key);
          int rank=rows.getColumnIndexOrThrow("canonical_rank");
          member.put("canonical_rank",rows.isNull(rank)?JSONObject.NULL:rows.getLong(rank));
          members.put(member);
        } while (rows.moveToNext());
        result.put("members",members).put("removalAuthorized",false);
        String payload=result.toString();
        if (payload.getBytes(StandardCharsets.UTF_8).length>1048576) {
          throw new IllegalStateException("Output bound");
        }
        System.out.println(payload);
      }
    } catch (Exception failure) {
      // Class only: do not expose SQLite text containing private IDs or paths.
      System.out.println("{\"error\":\"retention_observation_failed\",\"failureType\":\""
          + failure.getClass().getSimpleName() + "\"}");
      System.exit(1);
    }
  }
}
