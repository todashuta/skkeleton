// Generates the Vim9 script data tables from the TypeScript implementation.
//
// Run from the repository root:
//   DENO_DIR="$(pwd)/.deno" deno run -A --config deno.json tools/gen/gen_tables.ts
//
// Note: the tables are copies, not shared code.  Generating them keeps the two
//       implementations from drifting apart on the data while the logic is
//       still being ported by hand, and test/run.sh diffs the generated files
//       against a fresh run so a drift shows up as a failing test.
import { romToHira } from "../../denops/skkeleton/kana/rom_hira.ts";
import { romToZen } from "../../denops/skkeleton/kana/rom_zen.ts";

function vimStr(s: string): string {
  if (!s.includes("'") && !/[\x00-\x1f]/.test(s)) {
    return "'" + s + "'";
  }
  return '"' + s
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\n/g, "\\n")
    .replace(/\r/g, "\\r")
    .replace(/\t/g, "\\t") + '"';
}

function dumpList(name: string, table: unknown[][], header: string): string {
  const rows = table.map(([k, v]) => {
    const key = vimStr(k as string);
    const val = Array.isArray(v)
      ? `[${(v as string[]).map(vimStr).join(", ")}]`
      : vimStr((v as { name: string }).name);
    return `  [${key}, ${val}],`;
  });
  return `vim9script\n${header}\nexport const ${name}: list<list<any>> = [\n${
    rows.join("\n")
  }\n]\n`;
}

// The `"key": "value"` tables are plain data in files that are not exported,
// so they are read as text instead of being imported.
async function dumpRecord(
  path: string,
  name: string,
  header: string,
): Promise<string> {
  const text = await Deno.readTextFile(path);
  const rows: string[] = [];
  for (const m of text.matchAll(/^\s*"((?:[^"\\]|\\.)*)":\s*"((?:[^"\\]|\\.)*)",$/gm)) {
    rows.push(`  ${vimStr(m[1])}: ${vimStr(m[2])},`);
  }
  if (rows.length === 0) {
    throw new Error(`no entries found in ${path}`);
  }
  return `vim9script\n${header}\nexport const ${name}: dict<string> = {\n${
    rows.join("\n")
  }\n}\n`;
}

const src = "# Generated from denops/skeleton, do not edit by hand.";

await Deno.writeTextFile(
  "autoload/skkeleton/vim9/kana/rom_hira.vim",
  dumpList("RomToHira", romToHira as unknown as unknown[][], src),
);
await Deno.writeTextFile(
  "autoload/skkeleton/vim9/kana/rom_zen.vim",
  dumpList("RomToZen", romToZen as unknown as unknown[][], src),
);
await Deno.writeTextFile(
  "autoload/skkeleton/vim9/kana/hira_kata_table.vim",
  await dumpRecord(
    "denops/skkeleton/kana/hira_kata.ts",
    "KatakanaTable",
    src,
  ),
);
await Deno.writeTextFile(
  "autoload/skkeleton/vim9/kana/hira_hankata_table.vim",
  await dumpRecord(
    "denops/skkeleton/kana/hira_hankata.ts",
    "HanKataTable",
    src,
  ),
);
await Deno.writeTextFile(
  "autoload/skkeleton/vim9/okuri_table.vim",
  await dumpRecord("denops/skkeleton/okuri.ts", "OkuriTable", src),
);
console.log("generated tables");
