// Generates expected values for the Vim9 script dictionary tests from the
// TypeScript implementation.  Run from the repository root:
//   DENO_DIR="$(pwd)/.deno" deno run -A --config deno.json tools/gen/gen_dict_expect.ts
import {
  Library,
  wrapDictionary,
} from "../../denops/skkeleton/dictionary.ts";
import { Dictionary as SkkDictionary } from "../../denops/skkeleton/sources/skk_dictionary.ts";
import { Dictionary as UserDictionary } from "../../denops/skkeleton/sources/user_dictionary.ts";
import encoding from "npm:encoding-japanese@^2.4.0";


const root = new URL("../../", import.meta.url).pathname;
const testdata = root + "denops/skkeleton/testdata/";
const outPath = root + "test/expected/dict_expected.json";

const globalJisyo = testdata + "globalJisyo";
const globalJisyo2 = testdata + "globalJisyo2";
const userJisyo = testdata + "userJisyo";
const numJisyo = testdata + "numJisyo";
const numIncludingJisyo = testdata + "numIncludingJisyo";
const newJisyoJson = testdata + "newJisyo.json";
const newJisyoYaml = testdata + "newJisyo.yaml";

// --- number conversion oracle -------------------------------------------
// convertNumber() is not exported, so go through NumberConvertWrapper with a
// dictionary that returns the pattern for the digit-less word.
class Stub {
  pattern: string;
  constructor(pattern: string) {
    this.pattern = pattern;
  }
  getHenkanResult(_type: string, word: string): Promise<string[]> {
    // The wrapper first queries the digit-less word, then the raw word.
    if (/[0-9]/.test(word)) {
      return Promise.resolve([]);
    }
    return Promise.resolve([this.pattern]);
  }
  getCompletionResult(): Promise<never[]> {
    return Promise.resolve([]);
  }
}

async function convert(pattern: string, entry: string): Promise<string> {
  const dict = wrapDictionary(new Stub(pattern) as never);
  const result = await (dict as unknown as {
    getHenkanResult(type: string, word: string): Promise<string[]>;
  }).getHenkanResult("okurinasi", entry);
  return result[0];
}

const numberValues = [
  0, 1, 2, 5, 9, 10, 11, 12, 19, 20, 21, 30, 42, 89, 90, 99, 100, 101, 110,
  111, 123, 200, 999, 1000, 1001, 1010, 1100, 1234, 9999, 10000, 10001,
  12345, 99999, 100000, 123456, 1000000, 1000001, 1234567, 10000000,
  12345678, 100000000, 123456789, 1000000000, 1234567890, 1000000000000,
  1234567890123, 9999999999999,
];

type NumTable = Record<string, string>;
const number: Record<string, NumTable> = {
  toKifu: {},
  toZenkaku: {},
  toKanjiModern: {},
  toKanjiClassic: {},
  toRoman: {},
  toDaiji: {},
};
const patterns: [string, string][] = [
  ["#", "123"],
  ["#0", "123"],
  ["#1", "123"],
  ["#2", "123"],
  ["#3", "123"],
  ["#4", "123"],
  ["#5", "123"],
  ["#6", "123"],
  ["#7", "123"],
  ["#8", "123"],
  ["#9", "123"],
  ["#9", "11"],
  ["#9", "111"],
  ["#1", "0"],
  ["#2", "0"],
  ["#5", "0"],
  ["#8", "0"],
  ["第#1回", "12"],
  ["#1番", "101"],
  ["#9おうて", "11おうて"],
  ["#1#2#3#5#8", "12"],
  ["#1#2#3#5#8", "1"],
  ["abc", "123"],
  ["#1abc#2", "45x67"],
  ["foo#", "foo9"],
];
for (const n of numberValues) {
  for (const [name, pattern] of [
    ["toKifu", "#9"],
    ["toZenkaku", "#1"],
    ["toKanjiModern", "#2"],
    ["toKanjiClassic", "#3"],
    ["toDaiji", "#5"],
  ] as const) {
    number[name][String(n)] = await convert(pattern, String(n));
  }
}
// toRoman() is O(result length) in cr-numeral: 10^12 would be 10^9 "M"s,
// so only moderate values are recorded here.
for (const n of numberValues.filter((n) => n <= 100000)) {
  number.toRoman[String(n)] = await convert("#8", String(n));
}
const conversions = [];
for (const [pattern, entry] of patterns) {
  conversions.push({ pattern, entry, result: await convert(pattern, entry) });
}

// --- helper -------------------------------------------------------------
const expected: Record<string, unknown> = {};

async function run(name: string, fn: () => Promise<unknown>): Promise<void> {
  expected[name] = await fn();
}

function henkan(lib: Library, type: "okuriari" | "okurinasi", word: string) {
  return lib.getHenkanResult(type, word);
}

function completion(lib: Library, prefix: string, feed: string) {
  return lib.getCompletionResult(prefix, feed);
}

function skk(path: string, encoding: string) {
  return SkkDictionary.fromFile(path, encoding);
}

async function user(path?: string, rankPath?: string) {
  const dic = new UserDictionary();
  if (path !== undefined) {
    await dic.load({ path, rankPath });
  }
  return dic;
}

async function tmpFiles(): Promise<{ dir: string; path: string; rank: string }> {
  const dir = await Deno.makeTempDir({ prefix: "skkeleton-dict-test-" });
  return { dir, path: dir + "/user.skk", rank: dir + "/rank.json" };
}

// --- skk dictionary / library cases ------------------------------------
await run("newJson", async () => {
  const lib = new Library([skk(newJisyoJson, "utf-8")], new UserDictionary());
  return {
    ari: await henkan(lib, "okuriari", "わるs"),
    nasi: await henkan(lib, "okurinasi", "あかね"),
  };
});

await run("newYaml", async () => {
  const lib = new Library([skk(newJisyoYaml, "utf-8")], new UserDictionary());
  return {
    ari: await henkan(lib, "okuriari", "わるs"),
    nasi: await henkan(lib, "okurinasi", "あかね"),
  };
});

await run("global", async () => {
  const lib = new Library([skk(globalJisyo, "euc-jp")], new UserDictionary());
  return {
    ari: await henkan(lib, "okuriari", "てすt"),
    nasi: await henkan(lib, "okurinasi", "てすと"),
  };
});

await run("globalAutoDetect", async () => {
  const lib = new Library([skk(globalJisyo, "")], new UserDictionary());
  return {
    ari: await henkan(lib, "okuriari", "てすt"),
    nasi: await henkan(lib, "okurinasi", "てすと"),
  };
});

await run("global2", async () => {
  const lib = new Library([skk(globalJisyo2, "utf-8")], new UserDictionary());
  return {
    nasiI: await henkan(lib, "okurinasi", "い"),
    nasiTesuto: await henkan(lib, "okurinasi", "てすと"),
    ariNothing: await henkan(lib, "okuriari", "てすt"),
    empty: await henkan(lib, "okurinasi", "なにこれ"),
  };
});

await run("num", async () => {
  const dic = wrapDictionary(skk(numJisyo, "euc-jp"));
  const lib = new Library([dic], new UserDictionary());
  return {
    ban: await henkan(lib, "okurinasi", "101ばん"),
    kifu11: await henkan(lib, "okurinasi", "11おうて"),
    kifu111: await henkan(lib, "okurinasi", "111おうて"),
    banSmall: await henkan(lib, "okurinasi", "3ばん"),
    completion: await completion(lib, "101ば", ""),
  };
});

await run("numIncluding", async () => {
  const dic = wrapDictionary(skk(numIncludingJisyo, "utf-8"));
  const lib = new Library([dic], new UserDictionary());
  return {
    cat2: await henkan(lib, "okurinasi", "cat2"),
    tokyo: await henkan(lib, "okurinasi", "1000001"),
  };
});

await run("userJisyoHenkan", async () => {
  const lib = new Library([], await user(userJisyo));
  return {
    nasi: await henkan(lib, "okurinasi", "ユーザー辞書"),
    ari: await henkan(lib, "okuriari", "ユーザー辞書"),
    missing: await henkan(lib, "okurinasi", "ほげ"),
  };
});

// --- completion cases ---------------------------------------------------
await run("completionUser", async () => {
  const lib = new Library([], await user(userJisyo));
  return {
    oneChar: await completion(lib, "ユ", ""),
    twoChars: await completion(lib, "ユー", ""),
    full: await completion(lib, "ユーザー辞書", ""),
    noMatch: await completion(lib, "ほ", ""),
    empty: await completion(lib, "", ""),
  };
});

await run("completionSkkAndUser", async () => {
  const dict = skk(globalJisyo2, "utf-8");
  const lib = new Library([dict], await user(userJisyo));
  return {
    tesu: await completion(lib, "てす", ""),
    tesuFeedT: await completion(lib, "てす", "t"),
    tesuFeedTo: await completion(lib, "てす", "to"),
    tesuto: await completion(lib, "てすと", ""),
    i: await completion(lib, "い", ""),
    iFeed: await completion(lib, "い", "i"),
    userPrefix: await completion(lib, "ユ", ""),
  };
});

await run("completionMerge", async () => {
  // A user dictionary entry that shares a candidate with the global one, to
  // check that Library gathers candidates in dictionary order and dedupes.
  const tmp = await tmpFiles();
  try {
    const userDic = await user();
    await Deno.writeTextFile(
      tmp.path,
      [
        ";; okuri-ari entries.",
        ";; okuri-nasi entries.",
        "てすと /ﾃｽﾄ/user/",
        "てす /てす/",
        "",
      ].join("\n"),
    );
    await userDic.load({ path: tmp.path });
    const lib = new Library([skk(globalJisyo2, "utf-8")], userDic);
    return {
      nasi: await henkan(lib, "okurinasi", "てすと"),
      completionTesu: await completion(lib, "てす", ""),
      completionTesuto: await completion(lib, "てすと", ""),
      completionFeed: await completion(lib, "てす", "t"),
      ranks: lib.getRanks("てす"),
    };
  } finally {
    await Deno.remove(tmp.dir, { recursive: true });
  }
});

await run("completionSort", async () => {
  // localeCompare() is used by the skk dictionary; make sure byte order in
  // Vim agrees for the strings an SKK dictionary can hold.
  const tmp = await tmpFiles();
  try {
    await Deno.writeTextFile(
      tmp.path,
      [
        ";; okuri-ari entries.",
        ";; okuri-nasi entries.",
        "あい /愛/",
        "あいう /愛雨/",
        "ア /あ/",
        "アア /ああ/",
        "ab /ab/",
        "あ /亜/",
        "てすと /テスト/",
        "テスト /test/",
        "",
      ].join("\n"),
    );
    const lib = new Library([skk(tmp.path, "utf-8")], new UserDictionary());
    return {
      a: await completion(lib, "あ", ""),
      ai: await completion(lib, "あい", ""),
      a2: await completion(lib, "ア", ""),
      te: await completion(lib, "て", ""),
      t: await completion(lib, "テ", ""),
    };
  } finally {
    await Deno.remove(tmp.dir, { recursive: true });
  }
});

// --- registration / ranks / persistence ---------------------------------
await run("register", async () => {
  const dic = new UserDictionary();
  const lib = new Library([], dic);
  await lib.registerHenkanResult("okurinasi", "test", "a");
  await lib.registerHenkanResult("okurinasi", "test", "b");
  const afterB = await henkan(lib, "okurinasi", "test");
  await lib.registerHenkanResult("okurinasi", "test", "a");
  const afterA = await henkan(lib, "okurinasi", "test");
  return { afterB, afterA };
});

await run("interop", async () => {
  const lib = new Library(
    [skk(globalJisyo, "euc-jp")],
    new UserDictionary(),
  );
  await lib.registerHenkanResult("okurinasi", "てすと", "test");
  const afterTest = await henkan(lib, "okurinasi", "てすと");
  await lib.registerHenkanResult("okurinasi", "てすと", "てすと");
  const afterTesuto = await henkan(lib, "okurinasi", "てすと");
  return { afterTest, afterTesuto };
});

await run("emptyCandidate", async () => {
  const dic = new UserDictionary();
  dic.registerHenkanResult("okurinasi", "ほげ", "");
  dic.registerHenkanResult("okuriari", "ほげ", "");
  return {
    nasi: await dic.getHenkanResult("okurinasi", "ほげ"),
    ari: await dic.getHenkanResult("okuriari", "ほげ"),
  };
});

await run("ranks", async () => {
  const dic = new UserDictionary();
  dic.registerHenkanResult("okurinasi", "ほげ", "hoge");
  dic.registerHenkanResult("okurinasi", "ぴよ", "piyo");
  await new Promise((r) => setTimeout(r, 3));
  dic.registerHenkanResult("okurinasi", "ほげほげ", "hogehoge");
  const a = dic.getRanks("ほげ")
    .sort((x, y) => y[1] - x[1])
    .map((e) => e[0]);
  await new Promise((r) => setTimeout(r, 3));
  dic.registerHenkanResult("okurinasi", "ほげ", "hoge");
  const b = dic.getRanks("ほげ")
    .sort((x, y) => y[1] - x[1])
    .map((e) => e[0]);
  const c = dic.getRanks("ぴよ").map((e) => e[0]);
  return { a, b, c };
});

// User dictionary file round trips.  Expected file contents are produced by
// the TypeScript implementation so the Vim9 port writes byte identical files.

// Write {text} as EUC-JP or Shift_JIS bytes, the way an SKK dictionary file
// from the wild is encoded.
function writeJisFile(path: string, text: string, to: "EUCJP" | "SJIS"): string {
  const bytes = encoding.convert(text, {
    to,
    from: "UNICODE",
    type: "array",
  });
  Deno.writeFileSync(path, new Uint8Array(bytes));
  return path;
}

async function writeUserFixture(dir: string, lines: string[]): Promise<string> {
  const path = dir + "/user.skk";
  await Deno.writeTextFile(path, lines.join("\n"));
  return path;
}

await run("saveContent", async () => {
  const tmp = await tmpFiles();
  try {
    const path = await writeUserFixture(tmp.dir, [
      "",
      ";; okuri-ari entries.",
      ";; okuri-nasi entries.",
      "あ /あ/",
      "",
    ]);
    const dic = new UserDictionary();
    await dic.load({ path });
    const before = await dic.getHenkanResult("okurinasi", "あ");
    dic.registerHenkanResult("okurinasi", "あ", "亜");
    await dic.save();
    const data = await Deno.readTextFile(path);
    return { before, data, line: data.split("\n").find((v) => v.startsWith("あ")) };
  } finally {
    await Deno.remove(tmp.dir, { recursive: true });
  }
});

await run("saveSortOrder", async () => {
  const tmp = await tmpFiles();
  try {
    const path = await writeUserFixture(tmp.dir, [
      ";; okuri-ari entries.",
      ";; okuri-nasi entries.",
      "",
    ]);
    const dic = new UserDictionary();
    await dic.load({ path });
    dic.registerHenkanResult("okuriari", "わるs", "悪");
    dic.registerHenkanResult("okuriari", "てすt", "テスト");
    dic.registerHenkanResult("okuriari", "あs", "亜");
    dic.registerHenkanResult("okurinasi", "てすと", "テスト");
    dic.registerHenkanResult("okurinasi", "あ", "亜");
    dic.registerHenkanResult("okurinasi", "あ", "唖");
    await dic.save();
    return { data: await Deno.readTextFile(path) };
  } finally {
    await Deno.remove(tmp.dir, { recursive: true });
  }
});

await run("loadAnnotation", async () => {
  const tmp = await tmpFiles();
  try {
    const path = await writeUserFixture(tmp.dir, [
      ";; okuri-ari entries.",
      "わるs /[わる/]悪/[わるs/]/",
      ";; okuri-nasi entries.",
      "あ /[あ/]亜/",
      "",
    ]);
    const dic = new UserDictionary();
    await dic.load({ path });
    const ari = await dic.getHenkanResult("okuriari", "わるs");
    const nasi = await dic.getHenkanResult("okurinasi", "あ");
    await dic.save();
    return { ari, nasi, data: await Deno.readTextFile(path) };
  } finally {
    await Deno.remove(tmp.dir, { recursive: true });
  }
});

await run("rankFile", async () => {
  const tmp = await tmpFiles();
  try {
    const path = await writeUserFixture(tmp.dir, [
      ";; okuri-ari entries.",
      ";; okuri-nasi entries.",
      "ほげ /hoge/",
      "ぴよ /piyo/",
      "",
    ]);
    await Deno.writeTextFile(tmp.rank, JSON.stringify(["piyo", "hoge"]));
    const dic = new UserDictionary();
    await dic.load({ path, rankPath: tmp.rank });
    const ranks = dic.getRanks("ほ");
    const ranksPi = dic.getRanks("ぴ");
    return { ranks, ranksPi };
  } finally {
    await Deno.remove(tmp.dir, { recursive: true });
  }
});

await run("rankFileSave", async () => {
  const tmp = await tmpFiles();
  try {
    const path = await writeUserFixture(tmp.dir, [
      ";; okuri-ari entries.",
      ";; okuri-nasi entries.",
      "",
    ]);
    const dic = new UserDictionary();
    await dic.load({ path, rankPath: tmp.rank });
    dic.registerHenkanResult("okurinasi", "ほげ", "hoge");
    dic.registerHenkanResult("okurinasi", "ぴよ", "piyo");
    await new Promise((r) => setTimeout(r, 3));
    dic.registerHenkanResult("okurinasi", "ほげほげ", "hogehoge");
    await dic.save();
    return {
      data: await Deno.readTextFile(path),
      rank: await Deno.readTextFile(tmp.rank),
    };
  } finally {
    await Deno.remove(tmp.dir, { recursive: true });
  }
});

await run("purge", async () => {
  const tmp = await tmpFiles();
  try {
    const path = await writeUserFixture(tmp.dir, [
      ";; okuri-ari entries.",
      ";; okuri-nasi entries.",
      "てすと /テスト/test/",
      "",
    ]);
    const dic = new UserDictionary();
    await dic.load({ path });
    dic.purgeCandidate("okurinasi", "てすと", "test");
    const afterOne = await dic.getHenkanResult("okurinasi", "てすと");
    dic.purgeCandidate("okurinasi", "てすと", "テスト");
    const afterAll = await dic.getHenkanResult("okurinasi", "てすと");
    dic.purgeCandidate("okurinasi", "てすと", "テスト");
    await dic.save();
    return { afterOne, afterAll, data: await Deno.readTextFile(path) };
  } finally {
    await Deno.remove(tmp.dir, { recursive: true });
  }
});

// --- encoded dictionaries (EUC-JP / Shift_JIS) --------------------------
await run("sjis", async () => {
  const tmp = await tmpFiles();
  try {
    const text = [
      ";; okuri-ari entries.",
      "てすt /テスト/",
      ";; okuri-nasi entries.",
      "あ /亜/唖/",
      "てすと /テスト/",
      "",
    ].join("\n");
    const path = writeJisFile(tmp.dir + "/sjis.skk", text, "SJIS");
    const autoDic = skk(path, "");
    const autoLib = new Library([autoDic], new UserDictionary());
    const explicitDic = skk(path, "sjis");
    return {
      autoNasi: await autoLib.getHenkanResult("okurinasi", "あ"),
      autoAri: await autoLib.getHenkanResult("okuriari", "てすt"),
      explicitNasi: await explicitDic.getHenkanResult("okurinasi", "あ"),
    };
  } finally {
    await Deno.remove(tmp.dir, { recursive: true });
  }
});

await run("eucMapping", async () => {
  // glibc iconv() and encoding-japanese disagree on six JIS X 0208
  // characters; the TypeScript version reads EUC-JP through encoding-japanese,
  // so a converted dictionary has to match its choice (e.g. ～ U+FF5E, ∥
  // U+2225) rather than glibc's (〜 U+301C, ‖ U+2016).  The fixture is
  // written as the raw EUC-JP bytes A1C1 A1C2 A1DD A1F1 A1F2 A2CC so that
  // both implementations decode exactly the same input.
  const tmp = await tmpFiles();
  try {
    const eucKey = [
      0xa1, 0xc1, 0xa1, 0xc2, 0xa1, 0xdd, 0xa1, 0xf1, 0xa1, 0xf2, 0xa2, 0xcc,
    ];
    const bytes = [
      ...new TextEncoder().encode(
        ";; okuri-ari entries.\n;; okuri-nasi entries.\n",
      ),
      ...eucKey,
      ...encoding.convert(" /x/\nあ /亜/\nい /井/\n", {
        to: "EUCJP",
        from: "UNICODE",
        type: "array",
      }),
    ];
    const path = tmp.dir + "/mapping.skk";
    Deno.writeFileSync(path, new Uint8Array(bytes));
    const windowsKey = "\uff5e\u2225\uff0d\uffe0\uffe1\uffe2";
    const unicodeKey = "\u301c\u2016\u2212\u00a2\u00a3\u00ac";
    const dic = skk(path, "euc-jp");
    const lib = new Library([dic], new UserDictionary());
    const autoDic = skk(path, "");
    const autoLib = new Library([autoDic], new UserDictionary());
    return {
      windowsKey: await lib.getHenkanResult("okurinasi", windowsKey),
      unicodeKey: await lib.getHenkanResult("okurinasi", unicodeKey),
      kana: await lib.getHenkanResult("okurinasi", "あ"),
      autoWindowsKey: await autoLib.getHenkanResult("okurinasi", windowsKey),
    };
  } finally {
    await Deno.remove(tmp.dir, { recursive: true });
  }
});

await run("eucAuto", async () => {
  // A larger EUC-JP dictionary.  Its bytes can be mistaken for UTF-8 by a
  // naive detector (the testdata files happen to be detected correctly), so
  // the readings have to be parsed before the encoding is trusted.
  const tmp = await tmpFiles();
  try {
    const lines = [";; okuri-ari entries.", ";; okuri-nasi entries."];
    for (let i = 0; i < 300; i++) {
      lines.push("あ".repeat((i % 4) + 1) + "い" + " /候補" + i + "/");
    }
    lines.push("");
    const path = writeJisFile(tmp.dir + "/auto.skk", lines.join("\n"), "EUCJP");
    const dic = skk(path, "");
    const lib = new Library([dic], new UserDictionary());
    return {
      a: await lib.getHenkanResult("okurinasi", "あ" + "い"),
      aa: await lib.getHenkanResult("okurinasi", "ああ" + "い"),
      aaa: await lib.getHenkanResult("okurinasi", "あああ" + "い"),
    };
  } finally {
    await Deno.remove(tmp.dir, { recursive: true });
  }
});

// --- output -------------------------------------------------------------
const result = {
  number: { ...number, convert: conversions },
  cases: expected,
};
await Deno.writeTextFile(outPath, JSON.stringify(result, null, 2) + "\n");
console.log("wrote", outPath);
