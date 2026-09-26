package com.coachsync;

import jakarta.persistence.Entity;
import jakarta.persistence.Persistence;
import jakarta.persistence.Table;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.config.BeanDefinition;
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.core.type.filter.AnnotationTypeFilter;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Generates the MySQL-dialect DDL to {@code target/generated-schema-mysql.sql}
 * for human review, with no live database.
 *
 * <p>Uses the standalone {@code coachsync-ddl} persistence unit
 * (src/test/resources/META-INF/persistence.xml). The explicit
 * {@code database-product-name} + {@code MySQLDialect} let Hibernate emit the
 * create script without ever opening a JDBC connection. Open the generated file
 * to review tables, columns, nullability, foreign keys, the element-collection
 * table, and the two unique constraints.
 */
class SchemaExportTest {

    private static final Path OUTPUT = Path.of("target/generated-schema-mysql.sql");

    @Test
    void generatesMysqlSchemaScript() throws Exception {
        Files.deleteIfExists(OUTPUT);

        Map<String, Object> props = new HashMap<>();
        props.put("jakarta.persistence.schema-generation.scripts.action", "create");
        props.put("jakarta.persistence.schema-generation.scripts.create-target", OUTPUT.toString());
        // Pin the dialect explicitly so Hibernate emits the script with NO JDBC
        // connection. In Hibernate 7 the dialect must be set this way for
        // connection-less generation; database-product-name alone is not enough.
        props.put("hibernate.dialect", "org.hibernate.dialect.MySQLDialect");
        props.put("jakarta.persistence.database-product-name", "MySQL");
        props.put("jakarta.persistence.database-major-version", "8");
        props.put("jakarta.persistence.database-minor-version", "0");
        props.put("hibernate.hbm2ddl.delimiter", ";");
        props.put("hibernate.format_sql", "true");

        Persistence.generateSchema("coachsync-ddl", props);

        assertTrue(Files.exists(OUTPUT), "DDL script should be generated at " + OUTPUT);
        String ddl = Files.readString(OUTPUT).toLowerCase();
        assertFalse(ddl.isBlank(), "DDL script should not be empty");

        // Drift guard: derive the expected tables by SCANNING com.coachsync.domain
        // for @Entity rather than hand-listing them, so adding an entity but
        // forgetting to register it in persistence.xml fails loudly here.
        List<String> entityTables = scanEntityTableNames();
        assertFalse(entityTables.isEmpty(), "entity scan found no @Entity classes");
        for (String table : entityTables) {
            assertTrue(ddl.contains("create table " + table),
                    "generated schema is missing a table for a scanned @Entity: " + table);
        }
        // The element-collection table is owned by SessionBlock (not its own @Entity).
        assertTrue(ddl.contains("create table session_block_prescribed_rep_durations"),
                "missing element-collection table");

        // MySQL-dialect specifics — guard against a dialect-config regression that
        // would silently emit non-MySQL DDL while the table assertions still pass.
        assertTrue(ddl.contains("engine=innodb"), "DDL is not MySQL/InnoDB dialect");
        assertTrue(ddl.contains("binary(16)"), "UUID PKs should render as binary(16) on MySQL");

        // The two documented unique constraints should be emitted.
        assertTrue(ddl.contains("uq_attendance_session_athlete"),
                "missing unique constraint on attendance (session, athlete)");
        assertTrue(ddl.contains("uq_performance_block_athlete_rep"),
                "missing unique constraint on performance (block, athlete, rep)");
    }

    /** Lower-cased table name of every @Entity under com.coachsync.domain. */
    private static List<String> scanEntityTableNames() {
        var scanner = new ClassPathScanningCandidateComponentProvider(false);
        scanner.addIncludeFilter(new AnnotationTypeFilter(Entity.class));
        List<String> tables = new ArrayList<>();
        for (BeanDefinition def : scanner.findCandidateComponents("com.coachsync.domain")) {
            try {
                Class<?> type = Class.forName(def.getBeanClassName());
                Table table = type.getAnnotation(Table.class);
                String name = (table != null && !table.name().isBlank())
                        ? table.name()
                        : type.getSimpleName();
                tables.add(name.toLowerCase());
            } catch (ClassNotFoundException e) {
                throw new IllegalStateException("scanned entity class not loadable", e);
            }
        }
        return tables;
    }
}
