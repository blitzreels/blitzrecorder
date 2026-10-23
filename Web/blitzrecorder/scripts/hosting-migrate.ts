import { hostingPool } from "../lib/hosting/db";
import { migrate } from "../lib/hosting/migrate";

migrate(new URL("../migrations/", import.meta.url))
  .then((applied) => console.log(applied.length ? `Applied ${applied.join(", ")}` : "Hosting database is up to date."))
  .catch((error) => { console.error(error instanceof Error ? error.message : "Hosting migration failed."); process.exitCode = 1; })
  .finally(() => hostingPool().end());
