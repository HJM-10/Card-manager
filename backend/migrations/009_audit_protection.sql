-- The app cannot write audit/outbox creation rows directly. Only this trigger
-- runs with the migration owner's privileges. Bind relation names at migration
-- time: neither caller search_path nor temporary tables can redirect its writes.
DO $migration$
DECLARE target_schema text := current_schema();
BEGIN
    EXECUTE format($definition$
        CREATE OR REPLACE FUNCTION %1$I.record_transaction_created()
        RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
        SET search_path = pg_catalog, pg_temp AS $body$
        BEGIN
            INSERT INTO %1$I.transaction_audit_events (transaction_id) VALUES (NEW.id);
            INSERT INTO %1$I.transaction_outbox (transaction_id) VALUES (NEW.id);
            RETURN NEW;
        END;
        $body$;
    $definition$, target_schema);
    EXECUTE format('REVOKE ALL ON FUNCTION %I.record_transaction_created() FROM PUBLIC', target_schema);
    EXECUTE format('REVOKE ALL ON TABLE %I.transaction_audit_events FROM PUBLIC', target_schema);
END;
$migration$;
