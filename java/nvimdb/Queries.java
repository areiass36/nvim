package nvimdb;

import java.io.BufferedWriter;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

/** Running statements, and turning their results into one line of JSON. */
public final class Queries {
    private final Connection connection;
    private final AtomicReference<Statement> running;

    public Queries(Connection connection, AtomicReference<Statement> running) {
        this.connection = connection;
        this.running = running;
    }

    /**
     * @param limit rows to return, 0 for everything. One extra is fetched to
     *              learn whether another page exists, which is cheaper than a
     *              second count(*) query.
     */
    public void query(StringBuilder out, long id, String sql, int limit, int offset, int timeoutSeconds)
            throws SQLException {
        long start = System.currentTimeMillis();
        try (Statement statement = connection.createStatement(ResultSet.TYPE_FORWARD_ONLY, ResultSet.CONCUR_READ_ONLY)) {
            running.set(statement);
            if (timeoutSeconds > 0) {
                tolerate(() -> statement.setQueryTimeout(timeoutSeconds));
            }
            if (limit > 0) {
                // The driver asks the server for this many and no more, which
                // beats rewriting the statement with a LIMIT the dialect may
                // spell differently.
                tolerate(() -> statement.setMaxRows(limit + offset + 1));
                tolerate(() -> statement.setFetchSize(Math.min(limit + 1, 1000)));
            }

            boolean hasResult = statement.execute(sql);
            if (!hasResult) {
                int updated = statement.getUpdateCount();
                out.append("{\"id\":").append(id).append(",\"ok\":true,\"updateCount\":").append(updated);
                out.append(",\"elapsedMs\":").append(System.currentTimeMillis() - start).append('}');
                return;
            }

            try (ResultSet rows = statement.getResultSet()) {
                writeResultSet(out, id, rows, limit, offset, start);
            }
        } finally {
            running.set(null);
        }
    }

    private void writeResultSet(StringBuilder out, long id, ResultSet rows, int limit, int offset, long start)
            throws SQLException {
        ResultSetMetaData meta = rows.getMetaData();
        int columnCount = meta.getColumnCount();

        // The MongoDB driver answers with a single column holding a document;
        // the grid wants one column per field.
        Documents documents = Documents.detect(meta, columnCount);

        List<String> names = new ArrayList<>();
        List<String> types = new ArrayList<>();
        // Where each column came from, which is what lets a cell be followed
        // back to the row it belongs to: a foreign key in a result is only
        // useful if the editor knows which table the value is a key into. A
        // document result has no tables, so these stay empty for one.
        List<String> tables = new ArrayList<>();
        List<String> schemas = new ArrayList<>();
        if (documents == null) {
            for (int i = 1; i <= columnCount; i++) {
                final int column = i;
                names.add(meta.getColumnLabel(i));
                types.add(Values.typeName(meta, i));
                tables.add(optional(() -> meta.getTableName(column)));
                schemas.add(optional(() -> meta.getSchemaName(column)));
            }
        }

        List<List<Object>> collected = new ArrayList<>();
        int skipped = 0;
        boolean hasMore = false;
        while (rows.next()) {
            if (skipped < offset) {
                skipped++;
                continue;
            }
            if (limit > 0 && collected.size() >= limit) {
                hasMore = true;
                break;
            }
            if (documents != null) {
                collected.add(documents.row(rows, names, types));
            } else {
                List<Object> row = new ArrayList<>(columnCount);
                for (int i = 1; i <= columnCount; i++) {
                    row.add(Values.read(rows, meta, i));
                }
                collected.add(row);
            }
        }

        if (documents != null) {
            // A field missing from an earlier document has to be filled in
            // once the later ones have revealed it.
            documents.pad(collected, names.size());
        }

        out.append("{\"id\":").append(id).append(",\"ok\":true,\"columns\":[");
        for (int i = 0; i < names.size(); i++) {
            if (i > 0) out.append(',');
            out.append("{\"name\":");
            Json.writeString(out, names.get(i));
            out.append(",\"type\":");
            Json.writeString(out, types.get(i));
            if (i < tables.size() && tables.get(i) != null) {
                out.append(",\"table\":");
                Json.writeString(out, tables.get(i));
            }
            if (i < schemas.size() && schemas.get(i) != null) {
                out.append(",\"schema\":");
                Json.writeString(out, schemas.get(i));
            }
            out.append('}');
        }
        out.append("],\"rows\":[");
        for (int r = 0; r < collected.size(); r++) {
            if (r > 0) out.append(',');
            Json.writeValue(out, collected.get(r));
        }
        out.append("],\"hasMore\":").append(hasMore);
        out.append(",\"elapsedMs\":").append(System.currentTimeMillis() - start).append('}');
    }

    public void exec(StringBuilder out, long id, String sql) throws SQLException {
        long start = System.currentTimeMillis();
        try (Statement statement = connection.createStatement()) {
            running.set(statement);
            boolean hasResult = statement.execute(sql);
            int updated = hasResult ? -1 : statement.getUpdateCount();
            out.append("{\"id\":").append(id).append(",\"ok\":true,\"updateCount\":").append(updated);
            out.append(",\"elapsedMs\":").append(System.currentTimeMillis() - start).append('}');
        } finally {
            running.set(null);
        }
    }

    /**
     * Check a statement without running it.
     *
     * Preparing it is enough: the driver sends the text to the server, which
     * parses it, resolves the names and describes the result. Syntax errors
     * and unknown columns come back here, and nothing is executed - no
     * rolled-back transaction, no triggers, none of the games the command line
     * clients needed.
     */
    public void validate(StringBuilder out, long id, String sql) throws SQLException {
        long start = System.currentTimeMillis();
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            running.set(statement);
            // Asking for the shape of the result forces the describe on the
            // drivers that would otherwise prepare lazily.
            try {
                statement.getMetaData();
            } catch (SQLException e) {
                // Some statements have no result shape (INSERT without
                // RETURNING); that is not a validation failure.
                if (!isShapeless(e)) {
                    throw e;
                }
            }
            out.append("{\"id\":").append(id).append(",\"ok\":true,\"valid\":true");
            out.append(",\"elapsedMs\":").append(System.currentTimeMillis() - start).append('}');
        } finally {
            running.set(null);
        }
    }

    /**
     * Apply a setting the driver may not have. Not every JDBC driver
     * implements every knob - MongoDB's refuses setQueryTimeout outright - and
     * a missing one is no reason to fail the query.
     */
    private static void tolerate(SqlAction action) {
        try {
            action.run();
        } catch (SQLException ignored) {
            // The driver does not support it; the query still runs.
        }
    }

    @FunctionalInterface
    private interface SqlAction {
        void run() throws SQLException;
    }

    /**
     * Read something JDBC describes as optional, and treat it as optional.
     *
     * getTableName and getSchemaName are the cases this exists for: DuckDB
     * answers both with an empty string, SQLite names the table but has no
     * schema layer to name, an expression has no table to come from on any
     * engine, and some drivers throw rather than say so. A result the user
     * asked for still has to come back.
     *
     * @return null for a value that is absent, empty or unreadable, so the
     *         caller leaves the field out instead of writing an empty name.
     */
    private static String optional(SqlText source) {
        try {
            String value = source.get();
            return value == null || value.isEmpty() ? null : value;
        } catch (SQLException | RuntimeException unsupported) {
            return null;
        }
    }

    @FunctionalInterface
    private interface SqlText {
        String get() throws SQLException;
    }

    private static boolean isShapeless(SQLException e) {
        String message = e.getMessage() == null ? "" : e.getMessage().toLowerCase();
        return message.contains("no results were returned")
                || message.contains("statement does not produce")
                || message.contains("not return a result set");
    }

    /**
     * Stream a result straight to a CSV file. Nothing is held in memory, so a
     * result far larger than the editor could show still exports.
     */
    public void exportCsv(StringBuilder out, long id, String sql, String path, String nullMarker)
            throws SQLException, IOException {
        long start = System.currentTimeMillis();
        long written = 0;
        try (Statement statement = connection.createStatement(ResultSet.TYPE_FORWARD_ONLY, ResultSet.CONCUR_READ_ONLY)) {
            running.set(statement);
            tolerate(() -> statement.setFetchSize(1000));
            try (ResultSet rows = statement.executeQuery(sql);
                    Writer file = new BufferedWriter(new OutputStreamWriter(
                            Files.newOutputStream(Path.of(path)), StandardCharsets.UTF_8))) {
                ResultSetMetaData meta = rows.getMetaData();
                int columnCount = meta.getColumnCount();
                for (int i = 1; i <= columnCount; i++) {
                    if (i > 1) file.write(',');
                    file.write(Csv.field(meta.getColumnLabel(i), nullMarker));
                }
                file.write('\n');
                while (rows.next()) {
                    for (int i = 1; i <= columnCount; i++) {
                        if (i > 1) file.write(',');
                        Object value = Values.read(rows, meta, i);
                        file.write(Csv.field(value == null ? null : String.valueOf(value), nullMarker));
                    }
                    file.write('\n');
                    written++;
                }
            }
        } finally {
            running.set(null);
        }
        out.append("{\"id\":").append(id).append(",\"ok\":true,\"rows\":").append(written);
        out.append(",\"elapsedMs\":").append(System.currentTimeMillis() - start).append('}');
    }

    /** Columns of a result, for the grid, without the rows. */
    public static Map<String, Object> describe(ResultSetMetaData meta) throws SQLException {
        Map<String, Object> shape = new LinkedHashMap<>();
        for (int i = 1; i <= meta.getColumnCount(); i++) {
            shape.put(meta.getColumnLabel(i), Values.typeName(meta, i));
        }
        return shape;
    }
}
