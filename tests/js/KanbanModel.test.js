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
  { id: "card-10-500000", column: "done", title: "Fix bug", priority: "high", createdAt: 10 });
check("entryFromInput: an invalid column id falls back to the first column",
  M.entryFromInput("Fix bug", "someday", "high", 10, 0.5).column, "todo");
check("entryFromInput: an invalid/omitted priority falls back to medium",
  M.entryFromInput("Fix bug", "todo", "urgent!!", 10, 0.5).priority, "medium");

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

check("addCard: appends to the end",
  M.addCard([{ id: "a", column: "todo", title: "A", createdAt: 1 }], { id: "b", column: "todo", title: "B", createdAt: 2 })
    .map(function(c) { return c.id; }), ["a", "b"]);

const threeCards = [
  { id: "a", column: "todo", title: "A", priority: "medium", createdAt: 1 },
  { id: "b", column: "todo", title: "B", priority: "medium", createdAt: 2 },
  { id: "c", column: "done", title: "C", priority: "medium", createdAt: 3 }
];

check("moveCard: updates just the matching card's column",
  M.moveCard(threeCards, "b", "done").map(function(c) { return c.column; }), ["todo", "done", "done"]);
check("moveCard: an unknown card id changes nothing",
  M.moveCard(threeCards, "z", "done"), threeCards);
check("moveCard: an invalid target column changes nothing (fails closed)",
  M.moveCard(threeCards, "b", "someday"), threeCards);
check("moveCard: preserves the card's own priority across the move",
  M.moveCard([{ id: "a", column: "todo", title: "A", priority: "high", createdAt: 1 }], "a", "done")[0].priority,
  "high");

check("removeCard: drops just the matching card",
  M.removeCard(threeCards, "b").map(function(c) { return c.id; }), ["a", "c"]);
check("removeCard: an unknown card id changes nothing",
  M.removeCard(threeCards, "z").length, 3);

check("setPriority: updates just the matching card's priority",
  M.setPriority(threeCards, "b", "high").map(function(c) { return c.priority; }), ["medium", "high", "medium"]);
check("setPriority: an unknown card id changes nothing",
  M.setPriority(threeCards, "z", "high"), threeCards);
check("setPriority: an invalid priority changes nothing (fails closed)",
  M.setPriority(threeCards, "b", "urgent!!"), threeCards);

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
