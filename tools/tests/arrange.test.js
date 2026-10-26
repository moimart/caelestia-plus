// The display arrangement logic (shell/modules/nexus/pages/displays/arrange.js):
// where a dragged display lands, and which ones the pointer can reach.
//   node tools/tests/arrange.test.js
const fs = require("fs");
const src = fs.readFileSync(require("path").join(__dirname, "../../shell/modules/nexus/pages/displays/arrange.js"), "utf8").replace(".pragma library", "");
const A = new Function(src + "; return { snap, unreachable };")();
const dp = { name: "DP-1", x: 0, y: 0, width: 4608, height: 1296 };
const tv = { name: "HDMI-A-1", x: 384, y: -2160, width: 3840, height: 2160 };
const rects = [dp, tv];
// A typical canvas scale: 24 px on screen to snap, 10 to line up
const factor = 0.09, snapD = 24 / factor, alignD = 10 / factor;
let fail = 0;
const t = (label, x, y, want, rs = rects, name = "HDMI-A-1") => {
  const p = A.snap(rs, name, x, y, snapD, alignD);
  const ok = p.x === want[0] && p.y === want[1];
  if (!ok) fail++;
  console.log(`${ok ? "ok  " : "FAIL"} ${label}: dropped ${x},${y} -> ${p.x},${p.y}` + (ok ? "" : ` (wanted ${want})`));
};
t("just above, near centre", 300, -2200, [384, -2160]);
t("just above, off centre: slides freely", 1200, -2190, [1200, -2160]);
t("well above: stays, with a gap", 1000, -2600, [1000, -2600]);
t("a bit above, beyond the snap: stays", 1500, -2500, [1500, -2500]);
t("on top of DP-1: pushed to the nearest edge", 500, -1500, [500, -2160]);
t("to the right, near the edge", 4650, -300, [4608, -300]);
t("left side, near the edge: centres line up", -3800, -500, [-3840, -432]);
t("left side, far from centre: stays", -3800, -150, [-3840, -150]);
const gap = { ...tv, x: 1000, y: -2600 };
const same = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) fail++;
  console.log(`${ok ? "ok  " : "FAIL"} ${label}: ${JSON.stringify(got)}` + (ok ? "" : ` (wanted ${JSON.stringify(want)})`));
};
same("unreachable with a gap", A.unreachable([dp, gap], "DP-1"), ["HDMI-A-1"]);
same("unreachable when flush", A.unreachable([dp, tv], "DP-1"), []);
// Four displays in a row, a pair apart from the main group
const four = [dp, { name: "B", x: 4608, y: 0, width: 1920, height: 1080 }, { name: "C", x: 9000, y: 0, width: 1920, height: 1080 }, { name: "D", x: 10920, y: 0, width: 1920, height: 1080 }];
same("unreachable, a pair apart", A.unreachable(four, "DP-1"), ["C", "D"]);
process.exit(fail ? 1 : 0);
