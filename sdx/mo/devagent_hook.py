#!/usr/bin/env python3
"""devagent_hook — PreToolUse-хук для репозитория dev-agent системы (sim-kit 0.7.7, casino MOF-C-13, AG-038).

Правило: запись в каталоги исполнения инстанса (exec_paths) любой сессией — аренда МО или факт. dev-agent слил код
в exec_paths стенда без аренды, и МО узнало об этом из записки человека. Хук закрывает это:
  * если цель записи (Write/Edit или команда записи в Bash) лежит в exec_paths из .mesh/endpoint.yaml и на инстанс нет
    действующей аренды МО — хук шлёт конверт notice {"event": "exec_paths.write", ...} в свой .mesh/outbox;
    узел принимает его фактом env.foreign-write;
  * аренда определяется ТОЛЬКО по своему inbox: конверты lease.granted / lease.released, которые узел кладёт при операции
    с арендой инстанса и при role-switch (0.7.3, SDX-MO-1). Репозиторий узла не читается — узел может быть на другой машине;
  * on_write: deny — дополнительно блокирует запись (exit 2), пока аренды нет.
Политика отказа (SDX-MO-6): без .mesh/endpoint.yaml хук молчит всегда (exit 0, ничего не импортируется). При наличии
endpoint.yaml любая невозможность проверить цель (нет PyYAML, нечитаемый stdin, ошибка разбора) — в режиме notice
одна строка в stderr и exit 0 (fail-open), в режиме deny — exit 2 с причиной (fail-closed: PEP не может проверить цель).
Повторные записи одной сессии в один инстанс в окне NOTICE_WINDOW секунд конверт не порождают — считаются и уходят полем
suppressed следующего конверта (вопрос SDX №3).
Установка: в плагине SDX — hooks/hooks.json: PreToolUse, matcher Bash|Write|Edit|MultiEdit|NotebookEdit →
  PYTHONDONTWRITEBYTECODE=1 python3 "${CLAUDE_PLUGIN_ROOT}/sdx/mo/devagent_hook.py" (MESH_ENDPOINT_DIR берётся из CLAUDE_PROJECT_DIR).
Байткод: хук сам ставит sys.dont_write_bytecode до импорта mesh_endpoint (0.7.4) — __pycache__ в каталоге инструментов не появляется
и без переменной; переменная в примерах — на случай прямого запуска mesh_endpoint.py (ADR-013 SDX: плагин не пишет в свой корень).
Вручную: рядом с mesh_endpoint.py (например tools/mo/) и в .claude/settings.json:
  {"hooks": {"PreToolUse": [{"matcher": "Bash|Write|Edit|MultiEdit|NotebookEdit", "hooks": [{"type": "command",
    "command": "PYTHONDONTWRITEBYTECODE=1 python3 \\"$CLAUDE_PROJECT_DIR/tools/mo/devagent_hook.py\\""}]}]}}
Хук — второй PEP: границей он не является (AG-036); он делает запись видимой узлу.
"""
import datetime as dt, json, os, re, shlex, sys
from pathlib import Path

NOTICE_WINDOW = 600
os.environ.setdefault("MESH_ENDPOINT_DIR", os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
MESH_DIR = Path(os.environ["MESH_ENDPOINT_DIR"]) / ".mesh"
c_p = MESH_DIR / "endpoint.yaml"
if not c_p.exists():
    sys.exit(0)  # над этим репозиторием МО нет — хук не существует


def raw_mode():
    try:
        m = re.search(r"^\s*on_write\s*:\s*['\"]?(\w+)", c_p.read_text(encoding="utf-8"), re.M)
        return (m.group(1) if m else "notice").lower()
    except Exception:
        return "notice"


def cannot_check(why):
    if raw_mode() == "deny":
        print(f"DENY [MO-exec-paths]: PEP не может проверить цель записи — {why}. Режим deny: запись остановлена.", file=sys.stderr)
        sys.exit(2)
    print(f"devagent_hook: {why} — проверка exec_paths пропущена (режим notice)", file=sys.stderr)
    sys.exit(0)


sys.dont_write_bytecode = True  # каталог инструментов (плагин) в рантайме не пишется (0.7.4)
sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import mesh_endpoint as me
except (ImportError, SystemExit) as ex:
    cannot_check(f"нет mesh_endpoint/PyYAML ({ex})")

try:
    hook = json.load(sys.stdin)
    c = me.cfg()
except Exception as ex:
    cannot_check(f"вход хука/endpoint.yaml не разобран ({type(ex).__name__})")
MODE = str(c.get("on_write") or "notice").lower()  # регистр не важен — как в raw_mode (0.7.4)
exec_paths = [Path(os.path.expanduser(p)).resolve() for p in c.get("exec_paths") or []]
# 0.9: мандат разработки (.mesh/mandate.yaml, пишет узел) — область записи в репозитории: scope.paths (+ shared_paths допустимы, но
# слияние таких пакетов — решение человека). Запись вне области → notice {"event": "scope.write"} / deny по mandate.on_write (мягкая граница;
# жёсткая — аудит дельты у узла). Без мандата — только exec_paths, как в 0.7.
MANDATE = {}
try:
    mp = MESH_DIR / "mandate.yaml"
    if mp.exists():
        MANDATE = (me.yaml.safe_load(mp.read_text(encoding="utf-8")) or {}).get("mandate") or {}
except Exception:
    MANDATE = {}
SCOPE = (MANDATE.get("scope") or {}).get("paths") or []
SHARED = ((MANDATE.get("scope") or {}).get("shared_paths") or []) + ((MANDATE.get("scope") or {}).get("docs_paths") or [])
REPO_ROOT = MESH_DIR.parent.resolve()
if not exec_paths and not SCOPE:
    sys.exit(0)
ROOTS = exec_paths
tool = hook.get("tool_name", ""); ti = hook.get("tool_input") or {}
cwd0 = Path(hook.get("cwd") or os.getcwd())
# глаголы записи — по образцу guard MOF-C-3/4: пишут только в цель; чтение (git log, sed -n, npm ls) не цель
WRITE_VERBS = {"rm", "tee", "truncate", "dd", "touch", "mkdir", "chmod", "chown", "unzip"}  # все аргументы — цели; cp/mv/rsync/install/ln — см. DIRECTIONAL; tar — отдельно
GIT_WRITE = {"merge", "checkout", "pull", "reset", "rebase", "apply", "stash", "commit", "clean", "switch", "cherry-pick", "am", "clone"}
PKG_WRITE = {"install", "ci", "i", "add", "remove", "uninstall", "update", "upgrade", "run", "build", "rebuild", "link", "prune", "dedupe"}
PM2_WRITE = {"start", "restart", "reload", "stop", "delete", "resurrect", "save", "startOrRestart", "startOrReload"}
SEPS = {"&&", "||", ";", "|", "&"}


def inside(p, cwd):
    if re.match(r"^[\w.@-]+:", str(p)) and not str(p).startswith(("/", ".", "~")):
        return False  # user@host:/путь — удалённая цель rsync/scp, не локальный путь
    try:
        q = Path(os.path.expanduser(p))
        rp = (q if q.is_absolute() else cwd / q).resolve()
    except Exception:
        return False
    return any(rp == e or e in rp.parents for e in ROOTS)


DIRECTIONAL = {"cp", "mv", "rsync", "install", "ln"}   # пишут только в ПОСЛЕДНИЙ аргумент (moveio: `cp x build/` да, `tar czf a.tgz build` нет)
UNRESOLVED = []


def expand(w, cwd):
    """Раскрыть переменные окружения; нераскрытое ($VAR без значения) — не путь (casino D4: `$S/x.sh` принимался за путь в cwd)."""
    e = os.path.expandvars(w)
    if "$" in e:
        UNRESOLVED.append(w); return None
    return e


def redirect_target(w, nxt):
    """Цель перенаправления или None: `2>&1`, `>&2`, `&>/dev/null`, `>/dev/null` — не файлы (casino D4)."""
    if w in (">", ">>", ">|"):
        cand = nxt
    elif w in ("&>", "&>>"):
        cand = nxt
    else:
        m = re.match(r"^(\d?>>?|&>>?)(.+)$", w)
        if not m:
            return None
        cand = m.group(2)
    if not cand or cand.startswith("&") or cand.startswith("/dev/") or cand in (">", ">>"):
        return None
    return cand


def seg_targets(words, cwd):
    out = []
    if not words:
        return out
    for i, w in enumerate(words):
        cand = redirect_target(w, words[i + 1] if i + 1 < len(words) else None)
        if cand:
            cand = expand(cand, cwd)
            if cand and inside(cand, cwd):
                out.append(cand)
    v = os.path.basename(words[0]); args = [x for x in (expand(w, cwd) for w in words[1:] if not w.startswith("-")) if x]
    writes = False
    if v in DIRECTIONAL:
        if len(args) >= 2 and inside(args[-1], cwd):
            out.append(args[-1])
        return out
    if v in WRITE_VERBS:
        writes = True
    elif v == "tar":  # пишет только при распаковке (-x) в -C или при создании архива -f внутри exec_paths
        flags = "".join(w.lstrip("-") for w in words[1:2])
        if "x" in flags:
            if "-C" in words:
                j = words.index("-C")
                if j + 1 < len(words) and inside(words[j + 1], cwd):
                    out.append(words[j + 1])
            elif inside(".", cwd):
                out.append(str(cwd))
        elif "f" in flags and len(words) > 2 and inside(words[2], cwd):
            out.append(words[2])
        return out
    elif v == "sed":
        writes = any(re.match(r"^-[a-zA-Z]*i", w) or w.startswith("--in-place") for w in words[1:])  # только -i/--in-place пишет
    elif v == "git":
        if "-C" in words:
            j = words.index("-C")
            if j + 1 < len(words) and inside(words[j + 1], cwd) and any(x in words for x in GIT_WRITE):
                out.append(words[j + 1])
        elif any(x in words[1:] for x in GIT_WRITE) and inside(".", cwd):
            out.append(str(cwd))
    elif v in ("npm", "pnpm", "yarn", "npx"):
        writes = any(x in words[1:] for x in PKG_WRITE)
    elif v == "pm2":
        writes = any(x in words[1:] for x in PM2_WRITE)
    elif v == "make":
        writes = inside(".", cwd)  # цели make — не пути; запись — в текущий каталог
        if writes:
            out.append(str(cwd)); return out
    if writes:
        hit = [w for w in args if inside(w, cwd)]
        if hit:
            out.extend(hit)
        elif inside(".", cwd):  # команда записи без пути — пишет в текущий каталог
            out.append(str(cwd))
    return out


def collect():
    targets = []
    if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        fp = ti.get("file_path") or ti.get("notebook_path") or ""
        if inside(fp, cwd0):
            targets.append(fp)
    elif tool == "Bash":
        cmd = ti.get("command", "")
        try:
            words = shlex.split(cmd)
        except ValueError:
            words = cmd.split()
        cwd = cwd0; seg = []
        for w in words + ["&&"]:
            if w in SEPS:
                if seg and seg[0] == "cd" and len(seg) > 1:  # эффективный каталог для следующих сегментов
                    try:
                        cwd = (Path(os.path.expanduser(seg[1])) if os.path.isabs(os.path.expanduser(seg[1])) else cwd / seg[1]).resolve()
                    except Exception:
                        pass
                else:
                    targets.extend(seg_targets(seg, cwd))
                seg = []
            else:
                seg.append(w)
    return targets


# --- область мандата (0.9): записи в репозиторий вне scope.paths ---
if SCOPE:
    ROOTS = [REPO_ROOT]
    repo_targets = collect()
    import fnmatch as _fn
    def _in_scope(t):
        try:
            rel = str(Path(t).resolve().relative_to(REPO_ROOT))
        except Exception:
            return True
        if rel in (".", "") or rel.startswith(".mesh"):
            return True
        pats = list(SCOPE) + list(SHARED)
        return any(_fn.fnmatch(rel, p) or rel.startswith(p.rstrip("*").rstrip("/") + "/") or rel == p.rstrip("/") for p in pats)
    outside = sorted({t for t in repo_targets if not _in_scope(t)})
    if outside:
        smode = str(MANDATE.get("on_write") or "notice").lower()
        try:
            me.send("notice", {"event": "scope.write", "paths": outside[:20], "tool": tool, "mode": smode, "kit": me.KIT,
                               "executor": MANDATE.get("executor"), "mandate_digest": MANDATE.get("digest"), "session": hook.get("session_id"),
                               "ts": dt.datetime.now(dt.timezone.utc).isoformat()})
        except SystemExit as e:
            print(f"devagent_hook: конверт scope.write не отправлен: {e}", file=sys.stderr)
        if smode == "deny":
            print(f"DENY [MO-scope]: запись вне области мандата ({outside[0]}); область: {SCOPE}" + (f", общие: {SHARED}" if SHARED else "") +
                  ". Правка общих путей — отдельным пакетом с touches_shared; остальное — вне твоего мандата.", file=sys.stderr)
            sys.exit(2)
        print(f"devagent_hook: запись вне области мандата — {outside[:3]} (notice узлу; аудит дельты это отклонит)", file=sys.stderr)
    if not exec_paths:
        sys.exit(0)
    ROOTS = exec_paths
targets = collect()
if not targets:
    if UNRESOLVED:
        print(f"devagent_hook: путь с нераскрытой переменной не проверен: {UNRESOLVED[:3]} (цель записи неизвестна)", file=sys.stderr)
    sys.exit(0)

inst = c.get("instance")
try:
    me.pull(quiet=True)  # свой inbox: узел мог положить lease.granted/lease.released при последнем sync
    leased = inst in me.leases(c)
except Exception as ex:
    cannot_check(f"inbox не прочитан ({type(ex).__name__})")
if leased:
    sys.exit(0)  # запись под арендой МО (операция МО или role-switch) — видна узлу через аренду

# окно повторов: один конверт на сессию×инстанс за NOTICE_WINDOW секунд
key = f"{hook.get('session_id') or 'nosession'}|{inst}"
st_p = MESH_DIR / "hook-state.json"
try:
    st = json.loads(st_p.read_text(encoding="utf-8")) if st_p.exists() else {}
except Exception:
    st = {}
rec = st.get(key) or {}
t = dt.datetime.now(dt.timezone.utc)
suppressed = None
try:
    if rec.get("ts") and (t - dt.datetime.fromisoformat(rec["ts"])).total_seconds() < NOTICE_WINDOW:
        rec["count"] = int(rec.get("count", 0)) + 1; st[key] = rec; st_p.write_text(json.dumps(st))
        suppressed = rec["count"]
except Exception:
    suppressed = None
if suppressed is None:
    body = {"event": "exec_paths.write", "instance": inst, "paths": sorted(set(targets))[:20], "tool": tool, "mode": MODE, "kit": me.KIT,
            "unresolved": UNRESOLVED[:5] or None,
            "session": hook.get("session_id"), "endpoint": c.get("endpoint_id"), "ts": t.isoformat(), "suppressed_before": int(rec.get("count", 0)) or None}
    try:
        me.send("notice", body)
        st[key] = {"ts": t.isoformat(), "count": 0}; st_p.write_text(json.dumps(st))
    except SystemExit as e:
        print(f"devagent_hook: конверт не отправлен: {e}", file=sys.stderr)
if MODE == "deny":
    print(f"DENY [MO-exec-paths]: запись в каталог исполнения {inst} ({targets[0]}) без аренды МО. "
          f"Поставка — через операцию МО (artifact.offer → rollout) или аренда role-switch в узле {c.get('node_id')}.", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
