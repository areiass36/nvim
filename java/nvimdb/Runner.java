package nvimdb;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Base64;
import java.util.Properties;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicReference;

/**
 * One of these runs per database connection, and stays alive.
 *
 * Starting a JVM per query was measured and does not work: the DuckDB driver
 * unpacks a native library every time (~2.5 s) and the MongoDB driver starts a
 * JavaScript engine (~12 s on the first query). Alive, the same queries take
 * 1-2 ms and ~300 ms. Keeping the process also gives real cancellation
 * (Statement.cancel reaches the server) and one connection instead of one per
 * statement.
 *
 * Protocol, one message per line, because that is all this needs:
 *
 *   in   <id> TAB <op> [TAB <arg>]...      free-form args are base64
 *   out  {"id":<id>,"ok":true,...}         one JSON object per line
 *
 * Requests are read on the main thread and run on a single worker, so a
 * cancel can be read while a query is still running, and two statements never
 * touch the connection at once.
 */
public final class Runner {
    private final Connection connection;
    private final PrintWriter out;
    private final ExecutorService worker = Executors.newSingleThreadExecutor(task -> {
        Thread thread = new Thread(task, "nvim-db-query");
        thread.setDaemon(true);
        return thread;
    });
    private final AtomicReference<java.sql.Statement> running = new AtomicReference<>();
    private final Queries queries;
    private final Catalog catalog;

    public static void main(String[] args) throws Exception {
        // url, user, password: the password arrives on stdin's first line
        // instead of argv so it never shows up in the process table.
        String url = args.length > 0 ? args[0] : "";
        String user = args.length > 1 && !args[1].isEmpty() ? args[1] : null;

        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.UTF_8)));

        String password = input.readLine();
        if (password != null && !password.isEmpty()) {
            password = new String(Base64.getDecoder().decode(password), StandardCharsets.UTF_8);
        }

        Properties properties = new Properties();
        if (user != null) properties.setProperty("user", user);
        if (password != null && !password.isEmpty()) properties.setProperty("password", password);
        for (int i = 2; i < args.length; i++) {
            int equals = args[i].indexOf('=');
            if (equals > 0) {
                properties.setProperty(args[i].substring(0, equals), args[i].substring(equals + 1));
            }
        }

        Connection connection;
        try {
            connection = DriverManager.getConnection(url, properties);
        } catch (SQLException e) {
            StringBuilder error = new StringBuilder();
            error.append("{\"id\":0,\"ok\":false,\"fatal\":true,");
            error.append("\"state\":");
            Json.writeString(error, String.valueOf(e.getSQLState()));
            error.append(",\"code\":").append(e.getErrorCode());
            error.append(",\"message\":");
            Json.writeString(error, String.valueOf(e.getMessage()));
            error.append('}');
            out.println(error);
            out.flush();
            System.exit(1);
            return;
        }

        new Runner(connection, out).loop(input);
    }

    private Runner(Connection connection, PrintWriter out) {
        this.connection = connection;
        this.out = out;
        this.queries = new Queries(connection, running);
        this.catalog = new Catalog(connection);
        announceReady();
    }

    private void announceReady() {
        StringBuilder ready = new StringBuilder("{\"id\":0,\"ok\":true,\"ready\":true");
        try {
            var meta = connection.getMetaData();
            ready.append(",\"product\":");
            Json.writeString(ready, meta.getDatabaseProductName() + " " + meta.getDatabaseProductVersion());
            ready.append(",\"driver\":");
            Json.writeString(ready, meta.getDriverName() + " " + meta.getDriverVersion());
        } catch (SQLException ignored) {
            // A driver that cannot describe itself is still usable.
        }
        ready.append('}');
        send(ready.toString());
    }

    private synchronized void send(String line) {
        out.println(line);
        out.flush();
    }

    private static String decode(String value) {
        if (value == null || value.isEmpty()) return "";
        return new String(Base64.getDecoder().decode(value), StandardCharsets.UTF_8);
    }

    private void loop(BufferedReader input) throws Exception {
        String line;
        while ((line = input.readLine()) != null) {
            String[] fields = line.split("\t", -1);
            if (fields.length < 2) continue;
            long id = Long.parseLong(fields[0]);
            String op = fields[1];

            if (op.equals("close")) {
                break;
            }

            if (op.equals("cancel")) {
                // Handled here rather than on the worker, which is busy.
                java.sql.Statement statement = running.get();
                boolean cancelled = false;
                if (statement != null) {
                    try {
                        statement.cancel();
                        cancelled = true;
                    } catch (SQLException ignored) {
                        // Some drivers refuse; killing the process is the fallback.
                    }
                }
                send("{\"id\":" + id + ",\"ok\":true,\"cancelled\":" + cancelled + "}");
                continue;
            }

            if (op.equals("ping")) {
                send("{\"id\":" + id + ",\"ok\":true}");
                continue;
            }

            final String[] arguments = fields;
            worker.submit(() -> handle(id, op, arguments));
        }

        // Let the work already submitted finish: a close arriving while a
        // query is in flight should still return that query's answer.
        worker.shutdown();
        try {
            if (!worker.awaitTermination(30, java.util.concurrent.TimeUnit.SECONDS)) {
                worker.shutdownNow();
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            worker.shutdownNow();
        }
        try {
            connection.close();
        } catch (SQLException ignored) {
            // Shutting down anyway.
        }
    }

    private void handle(long id, String op, String[] fields) {
        StringBuilder response = new StringBuilder();
        try {
            switch (op) {
                case "query" -> queries.query(
                        response,
                        id,
                        decode(field(fields, 2)),
                        Integer.parseInt(orZero(field(fields, 3))),
                        Integer.parseInt(orZero(field(fields, 4))),
                        Integer.parseInt(orZero(field(fields, 5))));
                case "exec" -> queries.exec(response, id, decode(field(fields, 2)));
                case "validate" -> queries.validate(response, id, decode(field(fields, 2)));
                case "export" -> queries.exportCsv(
                        response, id, decode(field(fields, 2)), decode(field(fields, 3)), decode(field(fields, 4)));
                case "catalogs" -> catalog.catalogs(response, id);
                case "schemas" -> catalog.schemas(response, id, decode(field(fields, 2)));
                case "tables" -> catalog.tables(
                        response, id, decode(field(fields, 2)), decode(field(fields, 3)), decode(field(fields, 4)));
                case "columns" -> catalog.columns(
                        response, id, decode(field(fields, 2)), decode(field(fields, 3)), decode(field(fields, 4)));
                case "ddl" -> catalog.ddl(
                        response, id, decode(field(fields, 2)), decode(field(fields, 3)), decode(field(fields, 4)));
                default -> Errors.write(response, id, "unknown operation: " + op);
            }
        } catch (SQLException e) {
            // Whatever was written before the failure is half an object; the
            // error has to replace it, not follow it, or the line is not JSON.
            response.setLength(0);
            Errors.write(response, id, e);
        } catch (Exception e) {
            response.setLength(0);
            Errors.write(response, id, e.getClass().getSimpleName() + ": " + e.getMessage());
        }
        send(response.toString());
    }

    private static String field(String[] fields, int index) {
        return index < fields.length ? fields[index] : "";
    }

    private static String orZero(String value) {
        return value == null || value.isEmpty() ? "0" : value;
    }
}
