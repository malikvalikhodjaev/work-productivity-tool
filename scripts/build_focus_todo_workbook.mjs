import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const inputDir = process.argv[2];
const outputFile = process.argv[3];
if (!inputDir || !outputFile) {
  throw new Error("Expected the decoded JSONL directory and output XLSX path.");
}

const definitions = [
  { store: "Project", sheet: "Проекты", table: "FocusProjects" },
  { store: "Task", sheet: "Задачи", table: "FocusTasks" },
  { store: "Subtask", sheet: "Подзадачи", table: "FocusSubtasks" },
  { store: "Pomodoro", sheet: "Сеансы", table: "FocusSessions" },
];

async function readRows(store) {
  const source = await fs.readFile(path.join(inputDir, `db2_${store}.jsonl`), "utf8");
  return source.trimEnd().split("\n").filter(Boolean).map((line) => JSON.parse(line)._value);
}

const rowsByStore = Object.fromEntries(
  await Promise.all(definitions.map(async ({ store }) => [store, await readRows(store)])),
);
const projects = new Map(rowsByStore.Project.map((row) => [row.id, row]));
const tasks = new Map(rowsByStore.Task.map((row) => [row.id, row]));
const subtasks = new Map(rowsByStore.Subtask.map((row) => [row.id, row]));

function excelDate(ms) {
  if (typeof ms !== "number" || !Number.isFinite(ms) || ms < 946684800000 || ms > 4102444800000) {
    return "";
  }
  return ms / 86400000 + 25569 + 5 / 24;
}

function valueAsCell(value) {
  if (value === null || value === undefined) return "";
  if (typeof value === "number" || typeof value === "boolean" || typeof value === "string") return value;
  return JSON.stringify(value);
}

function detailColumns(store) {
  if (store === "Project") return [
    { name: "Родительский проект", get: (row) => projects.get(row.parentId)?.name ?? "" },
    { name: "Создано, Ташкент", get: (row) => excelDate(row.creationDate), date: true },
  ];
  if (store === "Task") return [
    { name: "Проект", get: (row) => projects.get(row.projectId)?.name ?? "" },
    { name: "Создано, Ташкент", get: (row) => excelDate(row.creationDate), date: true },
    { name: "Завершено, Ташкент", get: (row) => excelDate(row.finishedDate), date: true },
    { name: "Срок, Ташкент", get: (row) => excelDate(row.deadline), date: true },
  ];
  if (store === "Subtask") return [
    { name: "Задача", get: (row) => tasks.get(row.taskId)?.name ?? "" },
    { name: "Проект", get: (row) => projects.get(tasks.get(row.taskId)?.projectId)?.name ?? "" },
    { name: "Создано, Ташкент", get: (row) => excelDate(row.creationDate), date: true },
    { name: "Завершено, Ташкент", get: (row) => excelDate(row.finishedDate), date: true },
  ];
  return [
    { name: "Задача", get: (row) => tasks.get(row.taskId)?.name ?? "" },
    { name: "Подзадача", get: (row) => subtasks.get(row.subtaskId)?.name ?? "" },
    { name: "Проект", get: (row) => projects.get(tasks.get(row.taskId)?.projectId)?.name ?? "" },
    { name: "Задача найдена", get: (row) => tasks.has(row.taskId) },
    { name: "Завершено, Ташкент", get: (row) => excelDate(row.endDate), date: true },
    { name: "Длительность, мин", get: (row) => typeof row.interval === "number" ? row.interval / 60 : "", numeric: true },
    { name: "Длительность, ч", get: (row) => typeof row.interval === "number" ? row.interval / 3600 : "", numeric: true },
  ];
}

function sourceColumns(rows) {
  const keys = [...new Set(rows.flatMap((row) => Object.keys(row)))];
  const preferred = ["id", "name", "state", "isFinished", "projectId", "taskId", "subtaskId", "creationDate", "endDate", "finishedDate", "deadline", "interval", "estimatePomoNum", "actualPomoNum", "remark"];
  keys.sort((left, right) => {
    const a = preferred.indexOf(left);
    const b = preferred.indexOf(right);
    if (a !== -1 && b !== -1) return a - b;
    if (a !== -1) return -1;
    if (b !== -1) return 1;
    return left.localeCompare(right);
  });
  const result = [];
  for (const key of keys) {
    const maxLength = Math.max(0, ...rows.map((row) => String(valueAsCell(row[key])).length));
    const parts = Math.max(1, Math.ceil(maxLength / 30000));
    for (let part = 0; part < parts; part++) {
      result.push({
        name: parts === 1 ? key : `${key} [${part + 1}/${parts}]`,
        get: (row) => {
          const cell = valueAsCell(row[key]);
          return parts === 1 ? cell : String(cell).slice(part * 30000, (part + 1) * 30000);
        },
      });
    }
  }
  return result;
}

function columnLetter(index) {
  let number = index + 1;
  let label = "";
  while (number > 0) {
    number--;
    label = String.fromCharCode(65 + number % 26) + label;
    number = Math.floor(number / 26);
  }
  return label;
}

function writeDataSheet(workbook, definition) {
  const rows = rowsByStore[definition.store];
  const columns = [...detailColumns(definition.store), ...sourceColumns(rows)];
  const sheet = workbook.worksheets.add(definition.sheet);
  sheet.showGridLines = false;
  sheet.freezePanes.freezeRows(1);
  sheet.tabColor = definition.store === "Pomodoro" ? "#2775A9" : "#8496A8";
  const width = columns.length;
  const batchSize = 300;
  sheet.getRangeByIndexes(0, 0, 1, width).values = [columns.map((column) => column.name)];
  for (let start = 0; start < rows.length; start += batchSize) {
    const batch = rows.slice(start, start + batchSize).map((row) => columns.map((column) => column.get(row)));
    sheet.getRangeByIndexes(start + 1, 0, batch.length, width).values = batch;
  }
  const lastColumn = columnLetter(width - 1);
  const table = sheet.tables.add(`A1:${lastColumn}${rows.length + 1}`, true, definition.table);
  table.style = "TableStyleMedium2";
  table.showFilterButton = true;
  sheet.getRange(`A1:${lastColumn}1`).format.rowHeight = 28;
  sheet.getRange(`A1:${lastColumn}1`).format.font = { name: "Aptos", size: 10, bold: true, color: "#FFFFFF" };
  for (let index = 0; index < columns.length; index++) {
    const col = columnLetter(index);
    const name = columns[index].name;
    const widthUnits = name.includes("name") || name === "Задача" || name === "Проект" || name.includes("Название") ? 34
      : name.includes("remark") ? 42
      : name.includes("Ташкент") ? 21
      : name.endsWith("Id") || name === "id" ? 39
      : Math.min(30, Math.max(13, name.length + 2));
    sheet.getRange(`${col}1:${col}${rows.length + 1}`).format.columnWidth = widthUnits;
    if (columns[index].date) sheet.getRange(`${col}2:${col}${rows.length + 1}`).setNumberFormat("dd.mm.yyyy hh:mm");
    if (columns[index].numeric) sheet.getRange(`${col}2:${col}${rows.length + 1}`).setNumberFormat("0.00");
  }
  return { sheet, count: rows.length, columns: width };
}

const workbook = Workbook.create();
const overview = workbook.worksheets.add("Обзор");
overview.showGridLines = false;
overview.tabColor = "#1C2938";
overview.getRange("A1:F1").format.fill = "#17283B";
overview.getRange("A1:F1").format.rowHeight = 45;
overview.getRange("A1").values = [["Focus To-Do · локальная выгрузка"]];
overview.getRange("A1").format.font = { name: "Aptos Display", size: 18, bold: true, color: "#FFFFFF" };
overview.getRange("A3:B3").values = [["Показатель", "Значение"]];
overview.getRange("A3:B3").format = { fill: "#EAF1F6", font: { name: "Aptos", size: 11, bold: true, color: "#17324D" } };
const missingTaskLinks = rowsByStore.Pomodoro.filter((row) => !tasks.has(row.taskId)).length;
const hours = rowsByStore.Pomodoro.reduce((total, row) => total + (typeof row.interval === "number" ? row.interval : 0), 0) / 3600;
overview.getRange("A4:B9").values = [
  ["Проекты, записей", rowsByStore.Project.length],
  ["Задачи, записей", rowsByStore.Task.length],
  ["Подзадачи, записей", rowsByStore.Subtask.length],
  ["Сеансы, записей", rowsByStore.Pomodoro.length],
  ["Время сеансов, часов", hours],
  ["Сеансы без найденной задачи", missingTaskLinks],
];
overview.getRange("B8").setNumberFormat("0.00");
overview.getRange("A11").values = [["Как читать выгрузку"]];
overview.getRange("A11").format.font = { name: "Aptos", size: 12, bold: true, color: "#17324D" };
overview.getRange("A12:B16").values = [
  ["Источник", "Локальный снимок IndexedDB приложения Focus To-Do"],
  ["Строка", "Последняя актуальная версия записи по ключу в снимке"],
  ["Время", "Читаемые даты показаны в часовом поясе Asia/Tashkent (UTC+5); исходные Unix мс сохранены"],
  ["Длительность", "Поле interval исходной записи выражено в секундах; часы = interval / 3600"],
  ["Исходные поля", "Исходные названия полей сохранены; длинные значения remark разбиты на соседние колонки"],
];
overview.getRange("A18:B19").values = [
  ["Коды state", "Сохранены как в приложении, без предположений об их значении"],
  ["Группы", "Служебные записи Group и GroupUser не включены в эту выгрузку задач и времени"],
];
overview.getRange("A3:A19").format.columnWidth = 32;
overview.getRange("B3:B19").format.columnWidth = 65;
overview.getRange("A4:B19").format.font = { name: "Aptos", size: 10, color: "#243447" };
overview.getRange("A12:B19").format.rowHeight = 40;
overview.getRange("B12:B19").format.wrapText = true;

const completed = definitions.map((definition) => writeDataSheet(workbook, definition));
workbook.recalculate();
await fs.mkdir(path.dirname(outputFile), { recursive: true });
const preview = await workbook.render({ sheetName: "Обзор", range: "A1:B19", scale: 1, format: "png" });
await fs.writeFile(path.join(path.dirname(outputFile), "focus_todo_overview.png"), new Uint8Array(await preview.arrayBuffer()));
const xlsx = await SpreadsheetFile.exportXlsx(workbook);
await xlsx.save(outputFile);
console.log(JSON.stringify({ outputFile, overview: { projects: rowsByStore.Project.length, tasks: rowsByStore.Task.length, subtasks: rowsByStore.Subtask.length, sessions: rowsByStore.Pomodoro.length, hours, missingTaskLinks }, sheets: completed.map(({ sheet, count, columns }) => ({ name: sheet.name, rows: count, columns })) }, null, 2));
