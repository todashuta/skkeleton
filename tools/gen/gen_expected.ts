// Generates the expected results the Vim9 script implementation is diffed
// against.
//
// The TypeScript implementation is the reference: the same keys are sent
// through both and the resulting states are compared.  This is what makes the
// port checkable without a denops environment.
//
// Run from the repository root:
//   DENO_DIR="$(pwd)/.deno" deno run -A --config deno.json tools/gen/gen_expected.ts
import { config } from "../../denops/skkeleton/config.ts";
import { Context } from "../../denops/skkeleton/context.ts";
import { dispatch } from "../../denops/skkeleton/function/testutil.ts";
import { currentLibrary } from "../../denops/skkeleton/store.ts";

// The user dictionary is not written to: only learning in memory matters here.
config.userDictionary = "";
config.completionRankFile = "";
config.globalDictionaries = [];

const lib = await currentLibrary.get();

// A small dictionary, the same one the Vim test registers.
const dictionary: [("okurinasi" | "okuriari"), string, string][] = [
  ["okurinasi", "へんかん", "返還"],
  ["okurinasi", "へんかん", "変換"],
  ["okurinasi", "かんじ", "漢字"],
  ["okurinasi", "かんじ", "感じ"],
  ["okurinasi", "にほんご", "日本語"],
  ["okuriari", "おくr", "送"],
  ["okuriari", "えらn", "選"],
  ["okuriari", "うたがt", "疑"],
  ["okuriari", "うたがc", "疑"],
];
for (const [type, word, candidate] of dictionary) {
  await lib.registerHenkanResult(type, word, candidate);
}

const cases = [
  "kanji",
  "nihongo",
  "nihongoutteiki",
  "n n n n ",
  "@a",
  " na",
  ";",
  ";y",
  ";ya",
  ";ya;",
  ";henkan",
  ";henkan ",
  ";henkan  ",
  ";henkan  x",
  ";henkan \n",
  ";oku;ri",
  ";oku;ri ",
  ";era;nde",
  "a;ka",
  "a;ka;",
  "a;kanji ",
  ";kanji\n",
  ";kanji\nn",
  ";;",
  "a;kanji \u0008",
];

type Step = { keys: string; steps: string[]; output: string };
const results: Step[] = [];

// Note: a key sequence which runs the dictionary registration asks Vim for
//       input, which does not exist in this generator; such a case is reported
//       and skipped rather than being worked around with a stub denops that
//       would make the expected result a fiction.
const skipped: string[] = [];
for (const keys of cases) {
  const context = new Context();
  const steps: string[] = [];
  try {
    for (const key of keys) {
      await dispatch(context, key);
      steps.push(context.toString());
    }
    results.push({ keys, steps, output: context.preEdit.output("") });
  } catch (e) {
    skipped.push(`${keys}: ${e}`);
  }
}

await Deno.writeTextFile(
  "test/vim9/expected.json",
  JSON.stringify(
    { dictionary: dictionary.map(([type, word, candidate]) => [type, word, candidate]), cases: results },
    null,
    2,
  ) + "\n",
);
console.log(`generated ${results.length} cases`);
for (const s of skipped) console.log("skipped:", s);
