#!/usr/bin/env python3
"""devagent_hook — PreToolUse-хук для репозитория dev-agent системы (sim-kit 0.7.3, casino MOF-C-13, AG-038).

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
  python3 "${CLAUDE_PLUGIN_ROOT}/sdx/mo/devagent_hook.py" (MESH_ENDPOINT_DIR берётся из CLAUDE_PROJECT_DIR).
Вручную: рядом с mesh_endpoint.py (например tools/mo/) и в .claude/settings.json:
  {"hooks": {"PreToolUse": [{"matcher": "Bash|Write|Edit|MultiEdit|NotebookEdit", "hooks": [{"type": "command",
    "command": "python3 \\"$CLAUDE_PROJECT_DIR/tools/mo/devagent_hook.py\\""}]}]}}
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
exec_paths = [Path(os.path.expanduser(p)).resolve() for p in c.get("exec_paths") or []]
if not exec_paths:
    sys.exit(0)
tool = hook.get("tool_name", ""); ti = hook.get("tool_input") or {}
cwd0 = Path(hook.get("cwd") or os.getcwd())
# глаголы записи — по образцу guard MOF-C-3/4: пишут только в цель; чтение (git log, sed -n, npm ls) не цель
WRITE_VERBS = {"cp", "mv", "rm", "tee", "truncate", "ln", "dd", "install", "touch", "mkdir", "rsync", "chmod", "chown", "unzip", "tar"}
GIT_WRITE = {"merge", "checkout", "pull", "reset", "rebase", "apply", "stash", "commit", "clean", "switch", "cherry-pick", "am", "clone"}
PKG_WRITE = {"install", "ci", "i", "add", "remove", "uninstall", "update", "upgrade", "run", "build", "rebuild", "link", "prune", "dedupe"}
PM2_WRITE = {"start", "restart", "reload", "stop", "delete", "resurrect", "save", "startOrRestart", "startOrReload"}
SEPS = {"&&", "||", ";", "|", "&"}


def inside(p, cwd):
    try:
        q = Path(os.path.expanduser(p))
        rp = (q if q.is_absolute() else cwd / q).resolve()
    except Exception:
        return False
    return any(rp == e or e in rp.parents for e in exec_paths)


def seg_targets(words, cwd):
    out = []
    if not words:
        return out
    for i, w in enumerate(words):
        m = re.match(r"^\d?>>?(.+)$", w)
        cand = m.group(1) if m else (words[i + 1] if w in (">", ">>") and i + 1 < len(words) else None)
        if cand and inside(cand, cwd):
            out.append(cand)
    v = os.path.basename(words[0]); args = [w for w in words[1:] if not w.startswith("-")]
    writes = False
    if v in WRITE_VERBS:
        writes = True
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
        writes = True
    if writes:
        hit = [w for w in args if inside(w, cwd)]
        if hit:
            out.extend(hit)
        elif inside(".", cwd):  # команда записи без пути — пишет в текущий каталог
            out.append(str(cwd))
    return out


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
if not targets:
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
    body = {"event": "exec_paths.write", "instance": inst, "paths": sorted(set(targets))[:20], "tool": tool, "mode": c.get("on_write") or "notice",
            "session": hook.get("session_id"), "endpoint": c.get("endpoint_id"), "ts": t.isoformat(), "suppressed_before": int(rec.get("count", 0)) or None}
    try:
        me.send("notice", body)
        st[key] = {"ts": t.isoformat(), "count": 0}; st_p.write_text(json.dumps(st))
    except SystemExit as e:
        print(f"devagent_hook: конверт не отправлен: {e}", file=sys.stderr)
if (c.get("on_write") or "notice") == "deny":
    print(f"DENY [MO-exec-paths]: запись в каталог исполнения {inst} ({targets[0]}) без аренды МО. "
          f"Поставка — через операцию МО (artifact.offer → rollout) или аренда role-switch в узле {c.get('node_id')}.", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
