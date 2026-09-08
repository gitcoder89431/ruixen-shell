"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.notch", "KanbanModel.js"));

// ---- columns --------------------------------------------------------

check("defaultColumns: exactly 3, fixed order",
  M.defaultColumns(), [
    { id: "todo", label: "Todo" },
    { id: "in-progress", label: "In Progress" },
    { id: "done", label: "Done" }
  ]);

check("normalizeColumns: empty/missing input still yields all 3 defaults",
  M.normalizeColumns(null), M.defaultColumns());
check("normalizeColumns: a persisted custom label is kept",
  M.normalizeColumns([{ id: "todo", label: "Backlog" }]),
  [{ id: "todo", label: "Backlog" }, { id: "in-progress", label: "In Progress" }, { id: "done", label: "Done" }]);
check("normalizeColumns: an unknown column id is dropped, not added as a 4th",
  M.normalizeColumns([{ id: "todo", label: "X" }, { id: "someday", label: "Someday" }]).length, 3);
check("normalizeColumns: a blank persisted label falls back to the default",
  M.normalizeColumns([{ id: "done", label: "" }]),
  M.defaultColumns());

check("renameColumn: updates just the one column's label",
  M.renameColumn(M.defaultColumns(), "in-progress", "Doing").map(function(c) { return c.label; }),
  ["Todo", "Doing", "Done"]);
check("renameColumn: an unknown column id changes nothing",
  M.renameColumn(M.defaultColumns(), "someday", "X"), M.defaultColumns());
check("renameColumn: a blank label changes nothing (not stored as empty)",
  M.renameColumn(M.defaultColumns(), "todo", "   "), M.defaultColumns());

// ---- cards ------------------------------------------------------------

check("entryFromInput: a blank title yields null, nothing to store",
  M.entryFromInput("   ", "todo", "high", 10), null);
check("entryFromInput: a real card lands in the requested column",
  M.entryFromInput("Fix bug", "done", "high", 10, 0.5),
  { id: "card-10-500000", column: "done", title: "Fix bug", priority: "high", createdAt: 10, dueAt: 0, label: "", description: "" });
check("entryFromInput: an invalid column id falls back to the first column",
  M.entryFromInput("Fix bug", "someday", "high", 10, 0.5).column, "todo");
check("entryFromInput: an invalid/omitted priority falls back to medium",
  M.entryFromInput("Fix bug", "todo", "urgent!!", 10, 0.5).priority, "medium");
check("entryFromInput: an overlong title is trimmed to the cap, not rejected",
  M.entryFromInput("a".repeat(80), "todo", "high", 10, 0.5).title, "a".repeat(48));

check("normalizeCards: a card missing a title is dropped",
  M.normalizeCards([{ id: "a", column: "todo" }]), []);
check("normalizeCards: an invalid column on an otherwise-real card falls back to the first column",
  M.normalizeCards([{ id: "a", column: "someday", title: "X", createdAt: 1 }])[0].column, "todo");
check("normalizeCards: an invalid/missing priority falls back to medium",
  M.normalizeCards([{ id: "a", column: "todo", title: "X", createdAt: 1 }])[0].priority, "medium");
check("normalizeCards: a valid persisted priority is kept",
  M.normalizeCards([{ id: "a", column: "todo", title: "X", priority: "low", createdAt: 1 }])[0].priority, "low");
check("normalizeCards: a non-array input yields an empty list, not a crash",
  M.normalizeCards(null), []);
check("normalizeCards: a missing dueAt/label/description default to 0/empty/empty",
  M.normalizeCards([{ id: "a", column: "todo", title: "X", createdAt: 1 }])[0],
  { id: "a", column: "todo", title: "X", priority: "medium", createdAt: 1, dueAt: 0, label: "", description: "" });
check("normalizeCards: a valid persisted dueAt/label/description are kept",
  M.normalizeCards([{ id: "a", column: "todo", title: "X", createdAt: 1, dueAt: 500, label: "Github", description: "Needs review" }])[0],
  { id: "a", column: "todo", title: "X", priority: "medium", createdAt: 1, dueAt: 500, label: "Github", description: "Needs review" });
check("normalizeCards: a zero/negative persisted dueAt is treated as absent",
  M.normalizeCards([{ id: "a", column: "todo", title: "X", createdAt: 1, dueAt: -5 }])[0].dueAt, 0);
check("normalizeCards: an overlong persisted label is trimmed to the cap, not dropped",
  M.normalizeCards([{ id: "a", column: "todo", title: "X", createdAt: 1, label: "a".repeat(40) }])[0].label,
  "a".repeat(24));
check("normalizeCards: an overlong persisted title is trimmed to the cap, not dropped",
  M.normalizeCards([{ id: "a", column: "todo", title: "a".repeat(80), createdAt: 1 }])[0].title,
  "a".repeat(48));
check("normalizeCards: an overlong persisted description is trimmed to the cap, not dropped",
  M.normalizeCards([{ id: "a", column: "todo", title: "X", createdAt: 1, description: "a".repeat(80) }])[0].description,
  "a".repeat(60));

check("addCard: appends to the end",
  M.addCard([{ id: "a", column: "todo", title: "A", createdAt: 1 }], { id: "b", column: "todo", title: "B", createdAt: 2 })
    .map(function(c) { return c.id; }), ["a", "b"]);

const threeCards = [
  { id: "a", column: "todo", title: "A", priority: "medium", createdAt: 1 },
  { id: "b", column: "todo", title: "B", priority: "medium", createdAt: 2 },
  { id: "c", column: "done", title: "C", priority: "medium", createdAt: 3 }
];
// What threeCards looks like after passing through normalizeCards --
// every mutator here runs the input through that first, even on a
// no-op path, so a "changes nothing" assertion must compare against
// this (dueAt/label/description included), not the bare input literal
// above.
const threeCardsNormalized = threeCards.map(function(c) {
  return Object.assign({}, c, { dueAt: 0, label: "", description: "" });
});

check("moveCard: updates just the matching card's column",
  M.moveCard(threeCards, "b", "done").map(function(c) { return c.column; }), ["todo", "done", "done"]);
check("moveCard: an unknown card id changes nothing",
  M.moveCard(threeCards, "z", "done"), threeCardsNormalized);
check("moveCard: an invalid target column changes nothing (fails closed)",
  M.moveCard(threeCards, "b", "someday"), threeCardsNormalized);
check("moveCard: preserves the card's own priority across the move",
  M.moveCard([{ id: "a", column: "todo", title: "A", priority: "high", createdAt: 1 }], "a", "done")[0].priority,
  "high");
check("moveCard: preserves the card's own dueAt/label/description across the move",
  M.moveCard([{ id: "a", column: "todo", title: "A", createdAt: 1, dueAt: 500, label: "Github", description: "Needs review" }], "a", "done")[0],
  { id: "a", column: "done", title: "A", priority: "medium", createdAt: 1, dueAt: 500, label: "Github", description: "Needs review" });

check("removeCard: drops just the matching card",
  M.removeCard(threeCards, "b").map(function(c) { return c.id; }), ["a", "c"]);
check("removeCard: an unknown card id changes nothing",
  M.removeCard(threeCards, "z").length, 3);

check("setPriority: updates just the matching card's priority",
  M.setPriority(threeCards, "b", "high").map(function(c) { return c.priority; }), ["medium", "high", "medium"]);
check("setPriority: preserves the card's own dueAt/label/description",
  M.setPriority([{ id: "a", column: "todo", title: "A", createdAt: 1, dueAt: 500, label: "Github", description: "Needs review" }], "a", "high")[0],
  { id: "a", column: "todo", title: "A", priority: "high", createdAt: 1, dueAt: 500, label: "Github", description: "Needs review" });
check("setPriority: an unknown card id changes nothing",
  M.setPriority(threeCards, "z", "high"), threeCardsNormalized);
check("setPriority: an invalid priority changes nothing (fails closed)",
  M.setPriority(threeCards, "b", "urgent!!"), threeCardsNormalized);

// ---- renameCard ---------------------------------------------------

check("renameCard: updates just the matching card's title",
  M.renameCard(threeCards, "b", "New title").map(function(c) { return c.title; }), ["A", "New title", "C"]);
check("renameCard: preserves the card's own priority/dueAt/label/description",
  M.renameCard([{ id: "a", column: "todo", title: "A", priority: "high", createdAt: 1, dueAt: 500, label: "Github", description: "Needs review" }], "a", "B")[0],
  { id: "a", column: "todo", title: "B", priority: "high", createdAt: 1, dueAt: 500, label: "Github", description: "Needs review" });
check("renameCard: an unknown card id changes nothing",
  M.renameCard(threeCards, "z", "New title"), threeCardsNormalized);
check("renameCard: a blank title changes nothing (a card's title can never become empty)",
  M.renameCard(threeCards, "b", "   "), threeCardsNormalized);
check("renameCard: an overlong title is trimmed to the cap, not rejected",
  M.renameCard(threeCards, "b", "a".repeat(80))[1].title, "a".repeat(48));

// ---- setDueDate -----------------------------------------------------

check("setDueDate: updates just the matching card's dueAt",
  M.setDueDate(threeCards, "b", 500).map(function(c) { return c.dueAt; }), [0, 500, 0]);
check("setDueDate: an unknown card id changes nothing",
  M.setDueDate(threeCards, "z", 500), threeCardsNormalized);
check("setDueDate: zero clears an existing due date",
  M.setDueDate([{ id: "a", column: "todo", title: "A", createdAt: 1, dueAt: 500 }], "a", 0)[0].dueAt, 0);
check("setDueDate: a negative/non-finite value also clears it, not stored as-is",
  M.setDueDate([{ id: "a", column: "todo", title: "A", createdAt: 1, dueAt: 500 }], "a", NaN)[0].dueAt, 0);

// ---- setLabel ---------------------------------------------------------

check("setLabel: updates just the matching card's label",
  M.setLabel(threeCards, "b", "Github").map(function(c) { return c.label; }), ["", "Github", ""]);
check("setLabel: an empty string clears an existing label (a valid value, not rejected)",
  M.setLabel([{ id: "a", column: "todo", title: "A", createdAt: 1, label: "Github" }], "a", "")[0].label, "");
check("setLabel: an overlong label is trimmed to the cap, not rejected",
  M.setLabel(threeCards, "b", "a".repeat(40))[0 + 1].label, "a".repeat(24));
check("setLabel: an unknown card id changes nothing",
  M.setLabel(threeCards, "z", "Github"), threeCardsNormalized);

// ---- setDescription -----------------------------------------------

check("setDescription: updates just the matching card's description",
  M.setDescription(threeCards, "b", "Needs review").map(function(c) { return c.description; }), ["", "Needs review", ""]);
check("setDescription: an empty string clears an existing description (a valid value, not rejected)",
  M.setDescription([{ id: "a", column: "todo", title: "A", createdAt: 1, description: "Needs review" }], "a", "")[0].description, "");
check("setDescription: an overlong description is trimmed to the cap, not rejected",
  M.setDescription(threeCards, "b", "a".repeat(80))[1].description, "a".repeat(60));
check("setDescription: an unknown card id changes nothing",
  M.setDescription(threeCards, "z", "Needs review"), threeCardsNormalized);

// ---- isOverdue ----------------------------------------------------

check("isOverdue: a past dueAt on a non-Done card is overdue",
  M.isOverdue({ column: "todo", dueAt: 100 }, 200), true);
check("isOverdue: a future dueAt is not overdue",
  M.isOverdue({ column: "todo", dueAt: 300 }, 200), false);
check("isOverdue: no dueAt at all is never overdue",
  M.isOverdue({ column: "todo", dueAt: 0 }, 200), false);
check("isOverdue: a past dueAt on a Done card is NOT overdue (shipped, not late)",
  M.isOverdue({ column: "done", dueAt: 100 }, 200), false);
check("isOverdue: a null/missing card is never overdue",
  M.isOverdue(null, 200), false);

check("cardsInColumn: filtered to the one column, oldest first when priority ties",
  M.cardsInColumn(threeCards, "todo").map(function(c) { return c.id; }), ["a", "b"]);
check("cardsInColumn: an empty column yields an empty list",
  M.cardsInColumn(threeCards, "in-progress"), []);
check("cardsInColumn: high priority sorts before medium/low regardless of age",
  M.cardsInColumn([
    { id: "old-low", column: "todo", title: "Old, low", priority: "low", createdAt: 1 },
    { id: "new-high", column: "todo", title: "New, high", priority: "high", createdAt: 2 }
  ], "todo").map(function(c) { return c.id; }), ["new-high", "old-low"]);

check("nextColumnId: advances one step", M.nextColumnId("todo"), "in-progress");
check("nextColumnId: clamps at the last column, no wraparound", M.nextColumnId("done"), "done");
check("nextColumnId: an unknown column id falls back to the first", M.nextColumnId("someday"), "todo");

check("prevColumnId: regresses one step", M.prevColumnId("done"), "in-progress");
check("prevColumnId: clamps at the first column, no wraparound", M.prevColumnId("todo"), "todo");

check("emptyStateLabel: todo reads as good news, not placeholder copy",
  M.emptyStateLabel("todo"), "No further tasks");
check("emptyStateLabel: in-progress", M.emptyStateLabel("in-progress"), "Nothing in progress");
check("emptyStateLabel: done", M.emptyStateLabel("done"), "Nothing completed yet");
check("emptyStateLabel: an unknown column id still returns a fallback, not undefined",
  M.emptyStateLabel("someday"), "No cards");

summary();
