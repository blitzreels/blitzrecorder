import { readdir, readFile } from "node:fs/promises";
import { transaction } from "./db";

/** Every migration is idempotent; the ledger only spares later runs the table locks. */
export async function migrate(directory: URL): Promise<string[]> {
  const files = (await readdir(directory)).filter((file) => /^\d{3}-[a-z0-9-]+\.sql$/.test(file)).sort();
  return transaction(async (db) => {
    await db.query("SELECT pg_advisory_xact_lock(hashtext('hosting-migrations'))");
    await db.query("CREATE TABLE IF NOT EXISTS hosting_migrations (name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())");
    const applied = new Set((await db.query<{ name: string }>("SELECT name FROM hosting_migrations")).rows.map((row) => row.name));
    const pending = files.filter((file) => !applied.has(file));
    for (const file of pending) {
      await db.query(await readFile(new URL(file, directory), "utf8"));
      await db.query("INSERT INTO hosting_migrations(name) VALUES($1)", [file]);
    }
    return pending;
  });
}
