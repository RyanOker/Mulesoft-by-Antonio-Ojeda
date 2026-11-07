// Validates every API spec in the repository with AMF (the parser behind
// Anypoint Design Center and APIkit) and checks that each API's copy of the
// shared RAML library matches shared/raml/common-library.raml.
//
//   cd tools/raml-validator && npm install && npm run validate
//
// Exit code 1 if any spec has violations or a shared-library copy is stale.

import amf from "amf-client-js";
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const apisDir = join(repoRoot, "apis");
const canonicalLibrary = readFileSync(join(repoRoot, "shared", "raml", "common-library.raml"), "utf8");

const client = amf.RAMLConfiguration.RAML10().baseUnitClient();
let failed = false;

for (const app of readdirSync(apisDir).sort()) {
  const apiDir = join(apisDir, app, "src", "main", "resources", "api");
  const spec = join(apiDir, `${app}.raml`);
  if (!existsSync(spec)) continue; // e.g. batch apps without an HTTP interface

  const libraryCopy = join(apiDir, "common", "common-library.raml");
  if (existsSync(libraryCopy) && readFileSync(libraryCopy, "utf8") !== canonicalLibrary) {
    console.log(`FAIL ${app}: common/common-library.raml is out of date - run scripts/sync-raml-common.sh`);
    failed = true;
  }

  const parsed = await client.parse(pathToFileURL(spec).href);
  const report = parsed.conforms
    ? await client.validate(parsed.baseUnit)
    : parsed;
  const results = (report.results ?? []).filter((r) => r.severityLevel === "Violation");
  const warnings = (report.results ?? []).filter((r) => r.severityLevel === "Warning");

  if (results.length === 0) {
    console.log(`ok   ${app}${warnings.length ? ` (${warnings.length} warning(s))` : ""}`);
  } else {
    failed = true;
    console.log(`FAIL ${app}`);
  }
  for (const r of [...results, ...warnings]) {
    const where = r.location ? r.location.replace(pathToFileURL(repoRoot).href + "/", "") : "";
    const line = r.position?.start ? `:${r.position.start.line}` : "";
    console.log(`     ${r.severityLevel.toUpperCase()} ${where}${line} ${r.message}`);
  }
}

process.exit(failed ? 1 : 0);
