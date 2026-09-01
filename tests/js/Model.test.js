"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.weather", "Model.js"));

check(
  "parseLocationFile: valid JSON with coordinates",
  M.parseLocationFile('{"name":"  Tokyo  ","latitude":"35.6","longitude":"139.7"}'),
  { name: "Tokyo", latitude: 35.6, longitude: 139.7 }
);
check(
  "parseLocationFile: name-only (hand-edited weather.loc)",
  M.parseLocationFile('{"name":"Somewhere"}'),
  { name: "Somewhere", latitude: null, longitude: null }
);
check(
  "parseLocationFile: garbage input falls back to unset, not a throw",
  M.parseLocationFile("not json at all"),
  { name: "", latitude: null, longitude: null }
);
check(
  "parseLocationFile: empty/missing input falls back to unset",
  M.parseLocationFile(""),
  { name: "", latitude: null, longitude: null }
);

check("wttrLocationQuery: exact coordinates take priority", M.wttrLocationQuery("Tokyo", "35.6", "139.7"), "35.6,139.7");
check("wttrLocationQuery: name fallback when no coordinates", M.wttrLocationQuery("New York", "", ""), "New%20York");
check("wttrLocationQuery: nothing configured -> empty (IP auto-detect)", M.wttrLocationQuery("", "", ""), "");

check("roundedTemp: rounds down at .4", M.roundedTemp("18.4"), "18");
check("roundedTemp: rounds up at .5", M.roundedTemp("18.5"), "19");
check("roundedTemp: non-numeric input -> empty string, not NaN", M.roundedTemp("not a number"), "");
check("roundedTemp: missing value -> empty string", M.roundedTemp(undefined), "");

check("celsiusToFahrenheit: 0C is 32F", M.celsiusToFahrenheit("0"), 32);
check("celsiusToFahrenheit: 100C is 212F", M.celsiusToFahrenheit("100"), 212);

check("formatTemp: celsius suffix", M.formatTemp(18, false), "18°C");
check("formatTemp: fahrenheit suffix", M.formatTemp(64, true), "64°F");
check("formatTemp: missing value -> empty string", M.formatTemp(undefined, false), "");

check("normalizedUnit: trims and lowercases", M.normalizedUnit("  IMPERIAL  "), "imperial");
check("normalizedUnit: missing value -> empty string", M.normalizedUnit(undefined), "");

check("localeUsesImperial: en_US is imperial", M.localeUsesImperial("en_US"), true);
check("localeUsesImperial: en_GB is not imperial", M.localeUsesImperial("en_GB"), false);
check("localeUsesImperial: dotted locale form (en.US)", M.localeUsesImperial("en.US"), true);

check("countryUsesImperial: United States", M.countryUsesImperial("United States"), true);
check("countryUsesImperial: Germany", M.countryUsesImperial("Germany"), false);
check("countryUsesImperial: empty country -> unknown (null)", M.countryUsesImperial(""), null);

check("shouldUseImperial: explicit override wins over locale/country", M.shouldUseImperial("metric", "en_US", "United States"), false);
check("shouldUseImperial: country preference wins over locale when no override", M.shouldUseImperial("", "en_GB", "United States"), true);
check("shouldUseImperial: falls back to locale when country is unknown", M.shouldUseImperial("", "en_US", ""), true);

// Icon mapping compared against the underlying per-code lookup rather than
// a hardcoded glyph literal, so this test file never has to embed a
// private-use-area Nerd Font codepoint directly.
check(
  "iconForOpenMeteoCode: clear sky (0) maps to the same icon as raw code 113",
  M.iconForOpenMeteoCode(0, false),
  M.iconForCode(113, false)
);
check(
  "iconForOpenMeteoCode: heavy rain (65) maps to the same icon as raw code 308",
  M.iconForOpenMeteoCode(65, true),
  M.iconForCode(308, true)
);
check(
  "iconForOpenMeteoCode: unrecognized code falls back to raw code 119",
  M.iconForOpenMeteoCode(9999, false),
  M.iconForCode(119, false)
);

summary();
