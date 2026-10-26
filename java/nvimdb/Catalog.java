package nvimdb;

import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * The catalog, through DatabaseMetaData.
 *
 * This is the part JDBC pays for most: one implementation instead of six
 * hand-written SQL queries against pg_catalog, information_schema, sys.objects,
 * sqlite_master, duckdb_tables() and a Mongo aggregation - each with its own
 * quirks to remember. The driver knows how its own server answers.
 */
public final class Catalog {
    private static final int LIMIT = 500;

    private final Connection connection;

    public Catalog(Connection connection) {
        this.connection = connection;
    }

    private static String orNull(String value) {
        return value == null || value.isEmpty() ? null : value;
    }

    public void catalogs(StringBuilder out, long id) throws SQLException {
        DatabaseMetaData meta = connection.getMetaData();
        List<String> names = new ArrayList<>();
        try (ResultSet rows = meta.getCatalogs()) {
            while (rows.next() && names.size() < LIMIT) {
                names.add(rows.getString("TABLE_CAT"));
            }
        } catch (SQLException ignored) {
            // Not every driver has catalogs; the schema level covers those.
        }
        if (names.isEmpty()) {
            String current = connection.getCatalog();
            if (current != null && !current.isEmpty()) {
                names.add(current);
            }
        }
        writeNames(out, id, names);
    }

    public void schemas(StringBuilder out, long id, String catalog) throws SQLException {
        DatabaseMetaData meta = connection.getMetaData();
        List<String> names = new ArrayList<>();
        try (ResultSet rows = meta.getSchemas(orNull(catalog), null)) {
            while (rows.next() && names.size() < LIMIT) {
                names.add(rows.getString("TABLE_SCHEM"));
            }
        } catch (SQLException ignored) {
            // MySQL and SQLite have no schema layer.
        }
        writeNames(out, id, names);
    }

    public void tables(StringBuilder out, long id, String catalog, String schema, String pattern) throws SQLException {
        DatabaseMetaData meta = connection.getMetaData();
        String namePattern = pattern == null || pattern.isEmpty() ? "%" : "%" + pattern + "%";

        out.append("{\"id\":").append(id).append(",\"ok\":true,\"rows\":[");
        int count = 0;
        // Asking for a list of types does not work across drivers: DuckDB
        // answers with "BASE TABLE", others with "TABLE", and a type the driver
        // does not recognise silently returns nothing. So everything is
        // requested and the system objects are dropped here.
        try (ResultSet rows = meta.getTables(orNull(catalog), orNull(schema), namePattern, null)) {
            while (rows.next() && count < LIMIT) {
                String tableType = rows.getString("TABLE_TYPE");
                if (isSystem(tableType)) {
                    continue;
                }
                if (count > 0) out.append(',');
                out.append("{\"name\":");
                Json.writeString(out, String.valueOf(rows.getString("TABLE_NAME")));
                out.append(",\"kind\":");
                Json.writeString(out, kind(rows.getString("TABLE_TYPE")));
                String tableSchema = rows.getString("TABLE_SCHEM");
                if (tableSchema != null) {
                    out.append(",\"schema\":");
                    Json.writeString(out, tableSchema);
                }
                out.append('}');
                count++;
            }
        }
        out.append("]}");
    }

    private boolean isMongo() {
        try {
            return String.valueOf(connection.getMetaData().getDatabaseProductName()).toLowerCase().contains("mongo");
        } catch (SQLException e) {
            return false;
        }
    }

    /** How many documents to look at when working out a collection's fields. */
    private static final int SAMPLE_SIZE = 100;

    /**
     * A collection has no columns, so the fields of a sample stand in for
     * them. A field that holds different types in different documents is
     * reported once per type, which is the honest answer and the thing worth
     * knowing before writing a query against it.
     */
    private void sampleFields(StringBuilder out, long id, String collection) throws SQLException {
        java.util.LinkedHashMap<String, String> fields = new java.util.LinkedHashMap<>();
        java.util.LinkedHashMap<String, Integer> counts = new java.util.LinkedHashMap<>();

        String script = "db." + collection + ".find({})";
        try (java.sql.Statement statement = connection.createStatement()) {
            try {
                statement.setMaxRows(SAMPLE_SIZE);
            } catch (SQLException ignored) {
                // The driver caps it itself, or not at all.
            }
            try (ResultSet rows = statement.executeQuery(script)) {
                while (rows.next()) {
                    Object value = rows.getObject(1);
                    if (!(value instanceof java.util.Map<?, ?> document)) {
                        continue;
                    }
                    for (java.util.Map.Entry<?, ?> entry : document.entrySet()) {
                        String name = String.valueOf(entry.getKey());
                        String type = bsonType(entry.getValue());
                        String key = name + "\u0000" + type;
                        fields.putIfAbsent(key, type);
                        counts.merge(key, 1, Integer::sum);
                    }
                }
            }
        }

        out.append("{\"id\":").append(id).append(",\"ok\":true,\"rows\":[");
        int written = 0;
        for (java.util.Map.Entry<String, String> field : fields.entrySet()) {
            String name = field.getKey().substring(0, field.getKey().indexOf('\u0000'));
            if (written > 0) out.append(',');
            out.append("{\"name\":");
            Json.writeString(out, name);
            out.append(",\"type\":");
            Json.writeString(out, field.getValue());
            out.append(",\"nullable\":true,\"is_pk\":").append(name.equals("_id"));
            out.append(",\"count\":").append(counts.getOrDefault(field.getKey(), 0));
            out.append('}');
            written++;
        }
        out.append("]}");
    }

    private static String bsonType(Object value) {
        if (value == null) return "null";
        if (value instanceof java.util.Map) return "object";
        if (value instanceof java.util.List) return "array";
        if (value instanceof java.util.Date) return "date";
        if (value instanceof Boolean) return "bool";
        if (value instanceof byte[]) return "binary";
        return value.getClass().getSimpleName().toLowerCase();
    }

    private static boolean isSystem(String tableType) {
        if (tableType == null) return false;
        String type = tableType.toUpperCase();
        return type.startsWith("SYSTEM") || type.equals("INDEX") || type.equals("SEQUENCE");
    }

    private static String kind(String tableType) {
        if (tableType == null) return "table";
        return switch (tableType.toUpperCase()) {
            case "VIEW" -> "view";
            case "MATERIALIZED VIEW", "MATVIEW" -> "matview";
            case "COLLECTION" -> "collection";
            case "LOCAL TEMPORARY", "GLOBAL TEMPORARY", "TEMPORARY TABLE" -> "temp";
            default -> "table";
        };
    }

    public void columns(StringBuilder out, long id, String catalog, String schema, String table) throws SQLException {
        if (isMongo()) {
            // The JDBC driver's getColumns needs the Atlas SQL schema, which a
            // plain mongod does not have; it throws rather than returning
            // nothing. Sampling documents is what a collection can answer.
            sampleFields(out, id, table);
            return;
        }

        DatabaseMetaData meta = connection.getMetaData();

        Set<String> primaryKeys = new LinkedHashSet<>();
        try (ResultSet keys = meta.getPrimaryKeys(orNull(catalog), orNull(schema), table)) {
            while (keys.next()) {
                primaryKeys.add(keys.getString("COLUMN_NAME"));
            }
        } catch (SQLException ignored) {
            // Not every driver reports keys; the column list is still useful.
        }

        out.append("{\"id\":").append(id).append(",\"ok\":true,\"rows\":[");
        int count = 0;
        try (ResultSet rows = meta.getColumns(orNull(catalog), orNull(schema), table, "%")) {
            while (rows.next()) {
                if (count > 0) out.append(',');
                String name = rows.getString("COLUMN_NAME");
                out.append("{\"name\":");
                Json.writeString(out, String.valueOf(name));
                out.append(",\"type\":");
                Json.writeString(out, describeType(rows));
                // Not every driver fills in every optional column of the
                // metadata result; a missing one is not a reason to fail.
                out.append(",\"nullable\":").append(optionalInt(rows, "NULLABLE", DatabaseMetaData.columnNullable)
                        != DatabaseMetaData.columnNoNulls);
                out.append(",\"is_pk\":").append(primaryKeys.contains(name));
                String defaultValue = optionalString(rows, "COLUMN_DEF");
                if (defaultValue != null) {
                    out.append(",\"default_expr\":");
                    Json.writeString(out, defaultValue);
                }
                out.append('}');
                count++;
            }
        }
        out.append("]}");
    }

    private static String optionalString(ResultSet rows, String column) {
        try {
            return rows.getString(column);
        } catch (SQLException e) {
            return null;
        }
    }

    private static int optionalInt(ResultSet rows, String column, int fallback) {
        try {
            int value = rows.getInt(column);
            return rows.wasNull() ? fallback : value;
        } catch (SQLException e) {
            return fallback;
        }
    }

    /** varchar(50) and numeric(10,2) read better than varchar and numeric. */
    private static String describeType(ResultSet rows) throws SQLException {
        String type = String.valueOf(optionalString(rows, "TYPE_NAME")).toLowerCase();
        int size = optionalInt(rows, "COLUMN_SIZE", 0);
        int digits = optionalInt(rows, "DECIMAL_DIGITS", -1);
        boolean hasDigits = digits >= 0;
        if (type.contains("char") || type.contains("binary")) {
            return size > 0 ? type + "(" + size + ")" : type;
        }
        if ((type.contains("decimal") || type.contains("numeric")) && hasDigits) {
            return type + "(" + size + "," + digits + ")";
        }
        return type;
    }

    /**
     * There is no portable "show me the DDL": JDBC does not have one. The
     * column list with its keys and defaults is what every driver can answer,
     * and it is what the explorer shows.
     */
    public void ddl(StringBuilder out, long id, String catalog, String schema, String table) throws SQLException {
        columns(out, id, catalog, schema, table);
    }

    private static void writeNames(StringBuilder out, long id, List<String> names) {
        out.append("{\"id\":").append(id).append(",\"ok\":true,\"rows\":[");
        for (int i = 0; i < names.size(); i++) {
            if (i > 0) out.append(',');
            out.append("{\"name\":");
            Json.writeString(out, String.valueOf(names.get(i)));
            out.append('}');
        }
        out.append("]}");
    }
}
