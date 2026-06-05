#!/usr/bin/env bun

import { $ } from "bun";
import { existsSync, readFileSync } from "node:fs";

type ShellCommand = ReturnType<typeof $>;

type PackageInfo = {
  name: string;
  version: string;
  storePath: string;
};

type PackageVersionChange = {
  before: PackageInfo;
  after: PackageInfo;
};

type PackageChanges = {
  changed: PackageVersionChange[];
  rebuilt: PackageInfo[];
  added: PackageInfo[];
  removed: PackageInfo[];
};

type FileChange = {
  path: string;
  insertions: number;
  deletions: number;
};

type UpdateState = {
  runSwitch: boolean;
  previewStateMayNeedRestore: boolean;
  previewStateRestored: boolean;
};

type BrewCommand = "check" | "apply" | "cleanup";

type ParsedArgs =
  | { kind: "build" }
  | { kind: "switch" }
  | { kind: "add"; packageName: string }
  | { kind: "update"; runSwitch: boolean }
  | { kind: "brew"; command: BrewCommand; force: boolean }
  | { kind: "exit"; exitCode: number };

type Style = "green" | "red" | "yellow" | "dim" | "bold";

const USAGE = `Usage: scripts/hm.ts <command> [options]

Commands:
  build             Build the Home Manager configuration.
  switch            Build and activate the Home Manager configuration.
  add <package>     Add a nixpkgs package to Home Manager and verify it builds.
  update [--switch] Update nixpkgs and show evaluated package changes.
  brew <command>    Check or apply the repo-owned Brewfile.

Brew commands:
  check             Verify Brewfile artifacts are installed.
  apply             Install missing Brewfile artifacts.
  cleanup [--force] Show undeclared artifacts, or remove them with --force.

Options:
  -h, --help        Show this help text.

Environment:
  HM_HOME_CONFIGURATION  Override the last activated Home Manager profile.
`;

const STATUS_WIDTH = 12;
const REPO_DIR = `${import.meta.dir}/..`;
const DEFAULT_HOME_CONFIGURATION = "shane@macbook";
const LOCAL_WARP_HOME_CONFIGURATION = "warp-local";
const HOME_CONFIGURATION_ENV = "HM_HOME_CONFIGURATION";
const HOME_CONFIGURATION_STATE_PATH = `${Bun.env.HOME}/.local/state/home-manager/home-configuration`;
const LOCAL_WARP_PROFILE_BIN = `${Bun.env.HOME}/.nix-profile/bin/warp-terminal-experimental`;
const PACKAGE_MODULE_DISPLAY_PATH = "lib/packages.nix";
const PACKAGE_MODULE_PATH = `${REPO_DIR}/${PACKAGE_MODULE_DISPLAY_PATH}`;
const EXPLICIT_PACKAGES_EXPRESSION_PATH = "nix/explicit-packages.nix";
const HOME_CONFIGURATION_EXPRESSION = /^[A-Za-z0-9._-]+$/;
const NIX_PACKAGE_EXPRESSION = /^[A-Za-z_][A-Za-z0-9_'-]*(?:\.[A-Za-z_][A-Za-z0-9_'-]*)*$/;
const USE_COLOR = Bun.env.NO_COLOR === undefined && Bun.env.TERM !== "dumb";
const ANSI: Record<Style | "reset", string> = {
  reset: "\x1b[0m",
  green: "\x1b[32m",
  red: "\x1b[31m",
  yellow: "\x1b[33m",
  dim: "\x1b[2m",
  bold: "\x1b[1m",
};

class CommandFailure extends Error { }

function configuredHomeConfiguration(): string | undefined {
  const value = Bun.env[HOME_CONFIGURATION_ENV]?.trim();
  return value === "" ? undefined : value;
}

function stateHomeConfiguration(): string | undefined {
  if (Bun.env.HOME === undefined || !existsSync(HOME_CONFIGURATION_STATE_PATH)) return undefined;

  const value = readFileSync(HOME_CONFIGURATION_STATE_PATH, "utf8").trim();
  return value === "" ? undefined : value;
}

function currentProfileHomeConfiguration(): string | undefined {
  if (Bun.env.HOME === undefined || !existsSync(LOCAL_WARP_PROFILE_BIN)) return undefined;

  return LOCAL_WARP_HOME_CONFIGURATION;
}

function homeConfiguration(): string {
  const value =
    configuredHomeConfiguration() ??
    stateHomeConfiguration() ??
    currentProfileHomeConfiguration() ??
    DEFAULT_HOME_CONFIGURATION;

  if (!HOME_CONFIGURATION_EXPRESSION.test(value)) {
    throw new Error(`Invalid Home Manager configuration: ${value}`);
  }

  return value;
}

function homeFlakeRef(configuration = homeConfiguration()): string {
  return `.#${configuration}`;
}

function parseArgs(args: string[]): ParsedArgs {
  const [command, ...rest] = args;

  if (command === undefined || command === "-h" || command === "--help") {
    console.log(USAGE.trimEnd());
    return { kind: "exit", exitCode: 0 };
  }

  switch (command) {
    case "build":
      return parseNoOptionsCommand("build", rest);
    case "switch":
      return parseNoOptionsCommand("switch", rest);
    case "add":
      return parseAddArgs(rest);
    case "update":
      return parseUpdateArgs(rest);
    case "brew":
      return parseBrewArgs(rest);
    default:
      console.error(USAGE.trimEnd());
      return { kind: "exit", exitCode: 2 };
  }
}

function parseNoOptionsCommand(command: "build" | "switch", args: string[]): ParsedArgs {
  for (const arg of args) {
    switch (arg) {
      case "-h":
      case "--help":
        console.log(USAGE.trimEnd());
        return { kind: "exit", exitCode: 0 };
      default:
        console.error(USAGE.trimEnd());
        return { kind: "exit", exitCode: 2 };
    }
  }

  return { kind: command };
}

function parseAddArgs(args: string[]): ParsedArgs {
  const [packageName, ...rest] = args;

  if (packageName === undefined || packageName === "-h" || packageName === "--help") {
    console.log(USAGE.trimEnd());
    return { kind: "exit", exitCode: packageName === undefined ? 2 : 0 };
  }

  if (rest.length > 0) {
    console.error(USAGE.trimEnd());
    return { kind: "exit", exitCode: 2 };
  }

  return { kind: "add", packageName };
}

function parseUpdateArgs(args: string[]): ParsedArgs {
  let runSwitch = false;

  for (const arg of args) {
    switch (arg) {
      case "--switch":
        runSwitch = true;
        break;
      case "-h":
      case "--help":
        console.log(USAGE.trimEnd());
        return { kind: "exit", exitCode: 0 };
      default:
        console.error(USAGE.trimEnd());
        return { kind: "exit", exitCode: 2 };
    }
  }

  return { kind: "update", runSwitch };
}

function parseBrewArgs(args: string[]): ParsedArgs {
  const [command, ...rest] = args;

  if (command === undefined || command === "-h" || command === "--help") {
    console.log(USAGE.trimEnd());
    return { kind: "exit", exitCode: command === undefined ? 2 : 0 };
  }

  switch (command) {
    case "check":
    case "apply":
      return parseNoOptionsBrewCommand(command, rest);
    case "cleanup":
      return parseBrewCleanupArgs(rest);
    default:
      console.error(USAGE.trimEnd());
      return { kind: "exit", exitCode: 2 };
  }
}

function parseNoOptionsBrewCommand(command: "check" | "apply", args: string[]): ParsedArgs {
  for (const arg of args) {
    switch (arg) {
      case "-h":
      case "--help":
        console.log(USAGE.trimEnd());
        return { kind: "exit", exitCode: 0 };
      default:
        console.error(USAGE.trimEnd());
        return { kind: "exit", exitCode: 2 };
    }
  }

  return { kind: "brew", command, force: false };
}

function parseBrewCleanupArgs(args: string[]): ParsedArgs {
  let force = false;

  for (const arg of args) {
    switch (arg) {
      case "--force":
        force = true;
        break;
      case "-h":
      case "--help":
        console.log(USAGE.trimEnd());
        return { kind: "exit", exitCode: 0 };
      default:
        console.error(USAGE.trimEnd());
        return { kind: "exit", exitCode: 2 };
    }
  }

  return { kind: "brew", command: "cleanup", force };
}

function paint(text: string, style: Style): string {
  if (!USE_COLOR) return text;
  return `${ANSI[style]}${text}${ANSI.reset}`;
}

function status(
  verb: string,
  message: string,
  options: { stream?: "stdout" | "stderr"; style?: Style } = {},
): void {
  const style = options.style ?? "green";
  const line = `${paint(verb.padStart(STATUS_WIDTH), style)} ${message}`;

  if (options.stream === "stderr") {
    console.error(line);
  } else {
    console.log(line);
  }
}

function section(title: string): void {
  console.log(`${paint(title, "bold")}:`);
}

function subsection(title: string): void {
  console.log(`  ${title}:`);
}

function formatDurationMs(milliseconds: number): string {
  if (milliseconds < 1_000) return `${milliseconds}ms`;

  const seconds = milliseconds / 1_000;
  if (seconds < 60) return `${seconds.toFixed(1)}s`;

  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = seconds - minutes * 60;
  return `${minutes}m ${remainingSeconds.toFixed(1)}s`;
}

function elapsedSince(startedAt: number): string {
  return formatDurationMs(Date.now() - startedAt);
}

function pluralize(count: number, singular: string): string {
  return `${count} ${count === 1 ? singular : `${singular}s`}`;
}

function printIndented(text: string, stream: "stdout" | "stderr" = "stdout"): void {
  const write = stream === "stderr" ? console.error : console.log;
  const trimmed = text.trimEnd();

  if (trimmed.length === 0) {
    write("  no changes");
    return;
  }

  for (const line of trimmed.split("\n")) {
    write(`  ${line}`);
  }
}

function printCommandOutput(stdout: string, stderr: string): void {
  const output = combinedOutput(stdout, stderr);
  if (output.length === 0) return;

  console.error();
  sectionToStderr("Output");
  printIndented(output, "stderr");
}

function combinedOutput(stdout: string, stderr: string): string {
  return [stdout.trimEnd(), stderr.trimEnd()].filter((text) => text.length > 0).join("\n");
}

function sectionToStderr(title: string): void {
  console.error(`${paint(title, "bold")}:`);
}

async function withProgress<T>(message: string, startedAt: number, work: Promise<T>): Promise<T> {
  const timer = setInterval(() => {
    status("Waiting", `${message} (${elapsedSince(startedAt)})`, { style: "dim" });
  }, 10_000);

  try {
    return await work;
  } finally {
    clearInterval(timer);
  }
}

async function runStep(verb: string, message: string, command: ShellCommand): Promise<string> {
  const startedAt = Date.now();
  status(verb, message);

  const output = await withProgress(message, startedAt, command.quiet().nothrow());

  if (output.exitCode !== 0) {
    status("Failed", `${message} after ${elapsedSince(startedAt)}`, {
      stream: "stderr",
      style: "red",
    });
    printCommandOutput(output.stdout.toString(), output.stderr.toString());
    throw new CommandFailure(`${message} failed`);
  }

  return output.stdout.toString();
}

async function runBrewCleanupDryRun(): Promise<void> {
  const startedAt = Date.now();
  const message = "undeclared Homebrew artifacts";

  status("Checking", message);

  const output = await withProgress(
    message,
    startedAt,
    $`brew bundle cleanup --file Brewfile`.quiet().nothrow(),
  );
  const stdout = output.stdout.toString();
  const stderr = output.stderr.toString();

  if (output.exitCode !== 0 && !isBrewCleanupDryRun(stdout, stderr)) {
    status("Failed", `${message} after ${elapsedSince(startedAt)}`, {
      stream: "stderr",
      style: "red",
    });
    printCommandOutput(stdout, stderr);
    throw new CommandFailure(`${message} failed`);
  }

  const text = combinedOutput(stdout, stderr);
  if (text.length > 0) {
    console.log();
    section("Output");
    printIndented(text);
  }
}

function isBrewCleanupDryRun(stdout: string, stderr: string): boolean {
  const output = combinedOutput(stdout, stderr);

  return (
    output.includes("Run `brew bundle cleanup --force` to make these changes.") ||
    output.includes("Would uninstall") ||
    output.includes("Would untap") ||
    output.includes("Would `brew cleanup`")
  );
}

async function succeeds(command: ShellCommand): Promise<boolean> {
  const output = await command.quiet().nothrow();
  return output.exitCode === 0;
}

async function buildHomeManager(options: { printFinished?: boolean } = {}): Promise<void> {
  const startedAt = Date.now();
  const configuration = homeConfiguration();

  await runStep(
    "Building",
    `Home Manager generation (${configuration})`,
    $`home-manager build --flake ${homeFlakeRef(configuration)}`,
  );

  if (options.printFinished !== false) {
    status("Finished", `build in ${elapsedSince(startedAt)}`);
  }
}

async function switchHomeManager(options: { printFinished?: boolean } = {}): Promise<void> {
  const startedAt = Date.now();
  const configuration = homeConfiguration();

  await runStep(
    "Activating",
    `Home Manager generation (${configuration})`,
    $`home-manager switch --flake ${homeFlakeRef(configuration)}`,
  );

  if (options.printFinished !== false) {
    status("Finished", `switch in ${elapsedSince(startedAt)}`);
  }
}

type PackageListBounds = {
  startLine: number;
  endLine: number;
};

function validatePackageExpression(packageName: string): void {
  if (NIX_PACKAGE_EXPRESSION.test(packageName)) return;

  throw new Error(`Invalid package expression: ${packageName}`);
}

function packageListBounds(source: string): PackageListBounds {
  // lib/packages.nix is `pkgs: with pkgs; [ … ]` — the list opens with `[` on its
  // own line (after `with pkgs;`) and closes with a bare `]` (no trailing `;`).
  const lines = source.split("\n");
  const startLine = lines.findIndex((line) => line.trim() === "[");

  if (startLine === -1) {
    throw new Error(`Could not find the package list in ${PACKAGE_MODULE_DISPLAY_PATH}`);
  }

  const endLine = lines.findIndex((line, index) => index > startLine && /^\s*\]\s*$/.test(line));

  if (endLine === -1) {
    throw new Error(`Could not find the package list end in ${PACKAGE_MODULE_DISPLAY_PATH}`);
  }

  return { startLine, endLine };
}

function packageEntryName(line: string): string {
  return line.replace(/\s+#.*$/, "").trim();
}

function packageAlreadyDeclared(source: string, packageName: string): boolean {
  const bounds = packageListBounds(source);
  const lines = source.split("\n");

  return lines
    .slice(bounds.startLine + 1, bounds.endLine)
    .map(packageEntryName)
    .some((entry) => entry === packageName);
}

function insertPackage(source: string, packageName: string): string {
  const bounds = packageListBounds(source);
  const lines = source.split("\n");

  lines.splice(bounds.endLine, 0, `  ${packageName}`);

  return lines.join("\n");
}

async function addPackage(packageName: string): Promise<void> {
  const startedAt = Date.now();

  validatePackageExpression(packageName);

  const before = await Bun.file(PACKAGE_MODULE_PATH).text();

  if (packageAlreadyDeclared(before, packageName)) {
    status("Present", `${packageName} is already declared in ${PACKAGE_MODULE_DISPLAY_PATH}`, {
      style: "yellow",
    });
    return;
  }

  await Bun.write(PACKAGE_MODULE_PATH, insertPackage(before, packageName));
  status("Added", `${packageName} to ${PACKAGE_MODULE_DISPLAY_PATH}`);

  try {
    await buildHomeManager({ printFinished: false });
  } catch (error) {
    await Bun.write(PACKAGE_MODULE_PATH, before);
    status("Restored", `${PACKAGE_MODULE_DISPLAY_PATH} after failed build`, {
      stream: "stderr",
      style: "yellow",
    });
    throw error;
  }

  status("Finished", `add ${packageName} in ${elapsedSince(startedAt)}`);
}

async function runBrew(command: BrewCommand, force: boolean): Promise<void> {
  const startedAt = Date.now();

  switch (command) {
    case "check":
      await runStep("Checking", "Brewfile artifacts", $`brew bundle check --file Brewfile`);
      break;
    case "apply":
      await runStep("Installing", "Brewfile artifacts", $`brew bundle install --file Brewfile`);
      break;
    case "cleanup":
      if (force) {
        await runStep(
          "Cleaning",
          "undeclared Homebrew artifacts",
          $`brew bundle cleanup --file Brewfile --force`,
        );
      } else {
        await runBrewCleanupDryRun();
      }
      break;
  }

  const mode = command === "apply" ? "brew apply" : `brew ${command}`;
  status("Finished", `${mode} in ${elapsedSince(startedAt)}`);
}

async function restorePreviewState(state: UpdateState): Promise<void> {
  if (state.runSwitch || !state.previewStateMayNeedRestore || state.previewStateRestored) return;

  state.previewStateRestored = true;
  status("Restoring", "preview state");

  await Promise.all([
    $`git restore flake.lock`.quiet().nothrow(),
    $`rm -f result`.quiet().nothrow(),
  ]);
}

async function handleInterrupt(state: UpdateState, exitCode: number): Promise<void> {
  console.error();
  status("Interrupted", "restoring preview state", { stream: "stderr", style: "yellow" });
  await restorePreviewState(state);
  process.exit(exitCode);
}

function installInterruptHandlers(state: UpdateState): void {
  process.on("SIGINT", () => {
    void handleInterrupt(state, 130);
  });

  process.on("SIGTERM", () => {
    void handleInterrupt(state, 143);
  });
}

async function explicitPackages(message: string): Promise<string> {
  const configuration = homeConfiguration();
  return runStep(
    "Evaluating",
    `${message} (${configuration})`,
    $`env ${`${HOME_CONFIGURATION_ENV}=${configuration}`} nix eval --raw --impure --file ${EXPLICIT_PACKAGES_EXPRESSION_PATH}`,
  );
}

function parsePackages(output: string): Map<string, PackageInfo> {
  const packages = new Map<string, PackageInfo>();

  for (const line of output.split("\n")) {
    if (line.trim().length === 0) continue;

    const [name, version, storePath] = line.split("\t");
    if (name === undefined || version === undefined || storePath === undefined) {
      throw new Error(`Unexpected package description: ${line}`);
    }

    packages.set(name, { name, version, storePath });
  }

  return packages;
}

function packageChanges(
  before: Map<string, PackageInfo>,
  after: Map<string, PackageInfo>,
): PackageChanges {
  const changed: PackageVersionChange[] = [];
  const rebuilt: PackageInfo[] = [];
  const added: PackageInfo[] = [];
  const removed: PackageInfo[] = [];

  for (const pkg of after.values()) {
    const old = before.get(pkg.name);

    if (!old) {
      added.push(pkg);
      continue;
    }

    if (old.storePath !== pkg.storePath) {
      if (old.version === pkg.version) {
        rebuilt.push(pkg);
      } else {
        changed.push({ before: old, after: pkg });
      }
    }
  }

  for (const pkg of before.values()) {
    if (!after.has(pkg.name)) {
      removed.push(pkg);
    }
  }

  return { changed, rebuilt, added, removed };
}

function printPackageRows(packages: PackageInfo[]): void {
  const nameWidth = Math.max(...packages.map((pkg) => pkg.name.length));

  for (const pkg of packages) {
    console.log(`    ${pkg.name.padEnd(nameWidth)} ${pkg.version}`);
  }
}

function printChangedPackageRows(changed: PackageVersionChange[]): void {
  const nameWidth = Math.max(...changed.map(({ after }) => after.name.length));
  const versionWidth = Math.max(...changed.map(({ before }) => before.version.length));

  for (const { before, after } of changed) {
    console.log(
      `    ${after.name.padEnd(nameWidth)} ${before.version.padEnd(versionWidth)} -> ${after.version}`,
    );
  }
}

function printPackageChanges(changes: PackageChanges): void {
  const hasChanges =
    changes.changed.length > 0 ||
    changes.rebuilt.length > 0 ||
    changes.added.length > 0 ||
    changes.removed.length > 0;

  section("Packages");

  if (!hasChanges) {
    console.log("  no explicit package changes");
    return;
  }

  if (changes.changed.length > 0) {
    subsection("Changed");
    printChangedPackageRows(changes.changed);
  }

  if (changes.rebuilt.length > 0) {
    subsection("Rebuilt");
    printPackageRows(changes.rebuilt);
  }

  if (changes.added.length > 0) {
    subsection("Added");
    printPackageRows(changes.added);
  }

  if (changes.removed.length > 0) {
    subsection("Removed");
    printPackageRows(changes.removed);
  }
}

function parseFileChanges(output: string): FileChange[] {
  const changes: FileChange[] = [];

  for (const line of output.split("\n")) {
    if (line.trim().length === 0) continue;

    const [insertions, deletions, ...pathParts] = line.trim().split(/\s+/);
    if (insertions === undefined || deletions === undefined || pathParts.length === 0) {
      throw new Error(`Unexpected lockfile diff description: ${line}`);
    }

    const parsedInsertions = Number.parseInt(insertions, 10);
    const parsedDeletions = Number.parseInt(deletions, 10);

    if (Number.isNaN(parsedInsertions) || Number.isNaN(parsedDeletions)) {
      throw new Error(`Unexpected lockfile diff counts: ${line}`);
    }

    changes.push({
      path: pathParts.join(" "),
      insertions: parsedInsertions,
      deletions: parsedDeletions,
    });
  }

  return changes;
}

function printLockfileChanges(changes: FileChange[]): void {
  section("Lockfile");

  if (changes.length === 0) {
    console.log("  no changes");
    return;
  }

  for (const change of changes) {
    const changedLines = change.insertions + change.deletions;
    console.log(`  ${change.path}`);
    console.log(`    ${pluralize(changedLines, "line")} changed`);

    if (change.insertions > 0) {
      console.log(`    ${pluralize(change.insertions, "insertion")}`);
    }

    if (change.deletions > 0) {
      console.log(`    ${pluralize(change.deletions, "deletion")}`);
    }
  }
}

async function updateNixpkgs(runSwitch: boolean): Promise<void> {
  const startedAt = Date.now();
  const state: UpdateState = {
    runSwitch,
    previewStateMayNeedRestore: false,
    previewStateRestored: false,
  };
  installInterruptHandlers(state);

  status("Checking", "flake.lock");
  const [lockfileClean, stagedLockfileClean] = await Promise.all([
    succeeds($`git diff --quiet -- flake.lock`),
    succeeds($`git diff --cached --quiet -- flake.lock`),
  ]);

  if (!lockfileClean || !stagedLockfileClean) {
    throw new Error("flake.lock has local changes. Commit, stash, or restore it before updating.");
  }

  let finished = false;

  try {
    const before = parsePackages(await explicitPackages("current packages"));

    state.previewStateMayNeedRestore = true;
    await runStep("Updating", "nixpkgs", $`nix flake update nixpkgs`);

    const [afterOutput, lockfileDiff] = await Promise.all([
      explicitPackages("updated packages"),
      $`git diff --numstat -- flake.lock`.text(),
      buildHomeManager({ printFinished: false }),
    ]);
    const after = parsePackages(afterOutput);

    console.log();
    printPackageChanges(packageChanges(before, after));

    console.log();
    printLockfileChanges(parseFileChanges(lockfileDiff));

    if (state.runSwitch) {
      console.log();
      await switchHomeManager({ printFinished: false });
    } else {
      console.log();
    }

    finished = true;
  } finally {
    await restorePreviewState(state);
  }

  if (finished) {
    const mode = runSwitch ? "update and switch" : "preview";
    status("Finished", `${mode} in ${elapsedSince(startedAt)}`);
  }
}

async function main(): Promise<number> {
  const parsedArgs = parseArgs(Bun.argv.slice(2, undefined));
  if (parsedArgs.kind === "exit") return parsedArgs.exitCode;

  $.cwd(REPO_DIR);

  try {
    switch (parsedArgs.kind) {
      case "build":
        await buildHomeManager();
        break;
      case "switch":
        await switchHomeManager();
        break;
      case "add":
        await addPackage(parsedArgs.packageName);
        break;
      case "update":
        await updateNixpkgs(parsedArgs.runSwitch);
        break;
      case "brew":
        await runBrew(parsedArgs.command, parsedArgs.force);
        break;
    }

    return 0;
  } catch (error) {
    if (error instanceof CommandFailure) {
      return 1;
    }

    status("Error", error instanceof Error ? error.message : String(error), {
      stream: "stderr",
      style: "red",
    });
    return 1;
  }
}

if (import.meta.main) {
  process.exit(await main());
}
