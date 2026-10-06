import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import java.nio.charset.StandardCharsets;

/** Fixed, bounded READONLY projection for the private S7 comparison audit.
 * No arbitrary SQL/path, ROM reads, network requests or adoption/removal writes.
 * Artifacts and generations share one SQLite statement snapshot, including WAL.
 */
public final class RShopMigrationCacheSnapshot {
  // Limit source rows before JSON construction; CASE is lazy. The small result
  // fits one Android cursor window, not repeated windows across live writes.
  static final String SQL = """
      WITH artifacts AS (
        SELECT remote_artifact FROM games
        WHERE systemSlug=? AND remote_artifact IS NOT NULL LIMIT 2001
      ), states AS (
        SELECT scope,active,pending FROM drive_catalogue_state LIMIT 257
      )
      SELECT CASE
        WHEN (SELECT COUNT(*) FROM artifacts)>2000
          OR (SELECT COALESCE(SUM(length(CAST(remote_artifact AS BLOB))),0)
              FROM artifacts)>900000
          OR (SELECT COUNT(*) FROM states)>256
          OR (SELECT COALESCE(SUM(length(CAST(scope AS BLOB))),0) FROM states)>65536
        THEN '{"error":"projection_bound","artifactRows":' ||
          (SELECT COUNT(*) FROM artifacts) || ',"artifactBytes":' ||
          (SELECT COALESCE(SUM(length(CAST(remote_artifact AS BLOB))),0) FROM artifacts) ||
          ',"stateRows":' || (SELECT COUNT(*) FROM states) || ',"stateBytes":' ||
          (SELECT COALESCE(SUM(length(CAST(scope AS BLOB))),0) FROM states) || '}'
        ELSE '{"schema":"rshop.s7.cache.v1","platform":"' || ? ||
          '","artifacts":[' ||
          (SELECT COALESCE(group_concat(remote_artifact,','),'') FROM artifacts) ||
          '],"states":[' ||
          (SELECT COALESCE(group_concat('{"scope":' || scope ||
            ',"active":' || COALESCE(active,'null') ||
            ',"pending":' || COALESCE(pending,'null') || '}',','),'') FROM states) || ']}'
        END
      """;

  public static void main(String[] args) {
    try {
      if (args.length != 1 || !args[0].matches("[a-z0-9][a-z0-9_-]{0,63}")) {
        throw new IllegalArgumentException("An exact platform is required");
      }
      // run-as supplies this package's data directory/UID. Do not open another
      // app's cache or deserialize/copy a live database into host memory.
      try (SQLiteDatabase db = SQLiteDatabase.openDatabase("databases/rshop.db", null,
          SQLiteDatabase.OPEN_READONLY | SQLiteDatabase.NO_LOCALIZED_COLLATORS);
           Cursor row = db.rawQuery(SQL, new String[]{args[0], args[0]})) {
        if (!db.isReadOnly() || !row.moveToFirst()) {
          throw new IllegalStateException("Read-only projection required");
        }
        String payload = row.getString(0);
        if (payload == null || payload.getBytes(StandardCharsets.UTF_8).length > 1048576
            || row.moveToNext()) {
          throw new IllegalStateException("Invalid bounded projection");
        }
        System.out.println(payload);
      }
    } catch (Exception failure) {
      // No private identifiers or raw SQLite/provider exceptions in diagnostics.
      System.out.println("{\"error\":\"native_projection_failed\"}");
      System.exit(1);
    }
  }
}
