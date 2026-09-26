#!/usr/bin/env python3
"""Terminal chatbot for the worker8651 Gemini endpoint.

Usage:
    python3 gemini_chat.py
    python3 gemini_chat.py "explain rust ownership in two sentences"
    python3 gemini_chat.py --url http://localhost:8787/api/groovyrey/gemini
    python3 gemini_chat.py --install          accept the dependency install prompt
    python3 gemini_chat.py --no-install       never install, always fall back
    python3 gemini_chat.py --data-dir ./data keep history next to this file
    python3 gemini_chat.py --portable         force a .gemini_chat folder here

Portable use: copy gemini_chat.py to a flash drive and run it with any Python
3.8 or newer on that machine. Sessions and input history live in a
.gemini_chat folder next to the script when the script sits on removable media
and that folder is writable, otherwise they fall back to the home directory.
Read-only media is detected, nothing is written and the chat still runs.

The only hard requirement is the Python standard library. prompt_toolkit is
optional and upgrades the input line. When it is missing the script offers to
install it, creating a private venv in the home directory when the interpreter
cannot write to its own site-packages, then re-launching itself with it.

Env:
    GEMINI_ENDPOINT     override the endpoint URL
    GEMINI_MAX_TURNS    how many past turns to send as context (default 12)
    GEMINI_CHAT_DATA    data directory for sessions and input history
    GEMINI_CHAT_VENV    venv used for the optional dependency
    GEMINI_NO_INSTALL   set to 1 to never install anything
    NO_COLOR            disable ANSI colors
    NO_SPINNER          disable the thinking spinner
"""

import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import threading
from collections import deque
from datetime import datetime
from importlib.util import find_spec
from pathlib import Path

DEFAULT_ENDPOINT = "https://worker8651.reymartcenteno03.workers.dev/api/groovyrey/gemini"
PROMPT_LIMIT = 4000
CALLS_PER_MINUTE = 10
RATE_WINDOW = 60
RETRIES = 4
BOOTSTRAP_VENV = Path(os.environ.get("GEMINI_CHAT_VENV") or Path.home() / ".gemini_chat_venv")
BOOTSTRAP_ENV = "GEMINI_CHAT_BOOTSTRAPPED"
OPTIONAL_REQUIREMENTS = [("prompt_toolkit", "prompt_toolkit>=3.0")]
DATA_DIR = Path.home() / ".gemini_chat"
SESSION_DIR = DATA_DIR / "sessions"
HISTORY_FILE = DATA_DIR / "history"

RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
CYAN = "\033[36m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
SPINNER = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

COLOR = sys.stdout.isatty() and not os.environ.get("NO_COLOR")


def paint(text, color):
    return f"{color}{text}{RESET}" if COLOR else text


def read_int_env(name, fallback):
    try:
        return max(1, int(os.environ[name]))
    except (KeyError, ValueError):
        return fallback


MAX_TURNS = read_int_env("GEMINI_MAX_TURNS", 12)


def in_venv():
    return sys.prefix != sys.base_prefix


def is_removable(path):
    text = str(path)
    if any(text.startswith(root) for root in ("/media", "/mnt", "/run/media")):
        return True
    if os.name == "nt":
        drive = path.drive.upper()
        return bool(drive) and not drive.startswith("C")
    return False


def is_writable(path):
    probe = path / ".gemini_chat_probe"
    try:
        probe.write_text("")
        probe.unlink()
        return True
    except OSError:
        return False


def configure_data_dir(override=None, portable=False):
    global DATA_DIR, SESSION_DIR, HISTORY_FILE

    if override:
        DATA_DIR = Path(override).expanduser()
    elif portable:
        DATA_DIR = Path(__file__).resolve().parent / ".gemini_chat"
    elif os.environ.get("GEMINI_CHAT_DATA"):
        DATA_DIR = Path(os.environ["GEMINI_CHAT_DATA"]).expanduser()
    else:
        here = Path(__file__).resolve().parent
        DATA_DIR = here / ".gemini_chat" if is_removable(here) and is_writable(here) else Path.home() / ".gemini_chat"
    SESSION_DIR = DATA_DIR / "sessions"
    HISTORY_FILE = DATA_DIR / "history"
    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
    except OSError:
        pass
    return DATA_DIR


def venv_python(root):
    return root / ("Scripts/python.exe" if os.name == "nt" else "bin/python")


def run_pip(interpreter, requirements, extra=()):
    command = [
        str(interpreter),
        "-m",
        "pip",
        "install",
        "--disable-pip-version-check",
        "--no-input",
        *extra,
        *requirements,
    ]
    print(paint("running " + " ".join(command), DIM), flush=True)
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        print(paint("install timed out", RED))
        return False, command
    except OSError as err:
        print(paint(f"pip unavailable: {err}", RED))
        return False, command
    if result.returncode == 0:
        return True, command
    lines = [line for line in (result.stderr or result.stdout).splitlines() if line.strip()]
    print(paint(f"install failed: {lines[-1] if lines else 'unknown error'}", RED))
    return False, command


def create_venv(root):
    try:
        import venv
    except ImportError:
        print(paint("this python has no venv module, skipping isolated install", YELLOW))
        return None
    python = venv_python(root)
    print(paint(f"no writable site-packages, creating {root}", YELLOW), flush=True)
    try:
        venv.EnvBuilder(system_site_packages=True, with_pip=True, clear=False).create(str(root))
    except Exception as err:
        print(paint(f"venv creation failed: {err}", YELLOW))
        return None
    return python


def install_requirements(requirements):
    if not requirements:
        return True

    ok, command = run_pip(sys.executable, requirements)
    if ok:
        import importlib

        importlib.invalidate_caches()
        return True

    if not in_venv():
        ok, _ = run_pip(sys.executable, requirements, ["--user"])
        if ok:
            import importlib

            importlib.invalidate_caches()
            return True

    python = venv_python(BOOTSTRAP_VENV)
    if not python.exists():
        python = create_venv(BOOTSTRAP_VENV)
    if python is None:
        return False

    ok, command = run_pip(python, requirements)
    if not ok:
        return False

    if not os.environ.get(BOOTSTRAP_ENV):
        print(paint(f"installed in {BOOTSTRAP_VENV}, restarting", GREEN), flush=True)
        env = dict(os.environ, **{BOOTSTRAP_ENV: "1"})
        script = str(Path(__file__).resolve())
        sys.stdout.flush()
        os.execve(str(python), [str(python), script, *sys.argv[1:]], env)
    return True


def missing_requirements():
    missing = []
    for module, requirement in OPTIONAL_REQUIREMENTS:
        try:
            present = find_spec(module) is not None
        except (ImportError, ValueError):
            present = False
        if not present:
            missing.append(requirement)
    return missing


def ensure_requirements(assume_yes=False, assume_no=False):
    missing = missing_requirements()
    if not missing:
        return True
    names = ", ".join(dict(OPTIONAL_REQUIREMENTS).values())
    if assume_no or os.environ.get("GEMINI_NO_INSTALL") or os.environ.get(BOOTSTRAP_ENV):
        print(paint(f"optional packages missing: {names}", DIM))
        return False
    if not sys.stdin.isatty():
        print(paint(f"optional packages missing: {names}", DIM))
        return False
    if not assume_yes:
        try:
            answer = input(paint(f"install {names} for a better input line? [Y/n] ", YELLOW))
        except (EOFError, KeyboardInterrupt):
            print()
            return False
        if answer.strip().lower() not in ("", "y", "yes"):
            print(paint("skipped, using the plain input line", DIM))
            return False
    if not install_requirements(missing):
        print(paint(f"continuing without it, install later with: pip install {names}", DIM))
        return False
    return True


class GeminiClient:
    def __init__(self, endpoint, timeout=90):
        self.endpoint = endpoint
        self.timeout = timeout
        self.model = None
        self.calls = deque()

    def throttle(self):
        now = time.monotonic()
        while self.calls and now - self.calls[0] >= RATE_WINDOW:
            self.calls.popleft()
        if len(self.calls) >= CALLS_PER_MINUTE:
            wait = RATE_WINDOW - (now - self.calls[0]) + 1
            print(paint(f"local quota spent, waiting {wait:.0f}s", YELLOW), flush=True)
            time.sleep(wait)
        self.calls.append(time.monotonic())

    def ask(self, prompt):
        request = urllib.request.Request(
            self.endpoint,
            data=json.dumps({"prompt": prompt}).encode(),
            headers={"Content-Type": "application/json", "User-Agent": "gemini-chat/1.0"},
            method="POST",
        )
        backoff = 2.0
        for attempt in range(1, RETRIES + 1):
            self.throttle()
            try:
                with urllib.request.urlopen(request, timeout=self.timeout) as response:
                    payload = json.loads(response.read().decode())
                break
            except urllib.error.HTTPError as err:
                detail = err.read().decode(errors="replace").strip()[:300]
                if err.code == 429 and attempt < RETRIES:
                    print(paint("endpoint rate limit, retrying in 60s", YELLOW), flush=True)
                    time.sleep(RATE_WINDOW + 1)
                    continue
                if err.code >= 500 and attempt < RETRIES:
                    time.sleep(backoff)
                    backoff *= 2
                    continue
                raise RuntimeError(f"HTTP {err.code} {detail or err.reason}") from err
            except (urllib.error.URLError, TimeoutError, ConnectionError, json.JSONDecodeError) as err:
                if attempt < RETRIES:
                    time.sleep(backoff)
                    backoff *= 2
                    continue
                raise RuntimeError(f"request failed: {err}") from err

        text = (payload.get("text") or "").strip()
        if not text:
            raise RuntimeError("endpoint returned an empty answer")
        self.model = payload.get("model") or self.model
        return text


def build_prompt(history, message, limit=PROMPT_LIMIT):
    header = (
        "You are a chatbot by Reymart Centeno, a helpful assistant chatting in a "
        "terminal. If asked who made you, who you are, or who built you, say you are "
        "a chatbot by Reymart Centeno. Use the conversation below for context, then "
        "reply to the final user message. Reply with the answer only, no preamble."
    )
    budget = limit - len(header) - len(message) - 60
    chunks = []
    used = 0
    for turn in reversed(history[-MAX_TURNS:]):
        speaker = "User" if turn["role"] == "user" else "Assistant"
        chunk = f"{speaker}: {turn['text']}\n"
        if used + len(chunk) > budget:
            break
        chunks.append(chunk)
        used += len(chunk)
    chunks.reverse()

    parts = [header]
    if chunks:
        parts.append("Conversation:\n" + "".join(chunks))
    parts.append(f"User: {message}\nAssistant:")
    return "\n".join(parts)


def animate(text, step=6, speed=0.012):
    for index in range(0, len(text), step):
        sys.stdout.write(text[index : index + step])
        sys.stdout.flush()
        time.sleep(speed)
    sys.stdout.write("\n")
    sys.stdout.flush()


class Thinking:
    def __init__(self, label="", label_color=CYAN, enabled=True):
        self.enabled = enabled and sys.stdout.isatty() and not os.environ.get("NO_SPINNER")
        self.text = label
        self.label = paint(label, label_color)
        self.stop = threading.Event()
        self.thread = None
        self.started = 0.0

    def __enter__(self):
        if not self.enabled:
            return self
        self.started = time.monotonic()
        self.thread = threading.Thread(target=self._spin, daemon=True)
        self.thread.start()
        return self

    def _spin(self):
        frame = 0
        width = len(self.text)
        while not self.stop.is_set():
            tick = f" {SPINNER[frame % len(SPINNER)]} {time.monotonic() - self.started:4.1f}s"
            sys.stdout.write("\r" + self.label + paint(tick, DIM))
            sys.stdout.flush()
            width = max(width, len(self.text) + len(tick))
            frame += 1
            self.stop.wait(0.08)
        sys.stdout.write("\r" + " " * (width + 4) + "\r" + self.label)
        sys.stdout.flush()

    def __exit__(self, *exc):
        self.stop.set()
        if self.thread:
            self.thread.join()
        return False


def reply_block(client, prompt, animate_output):
    label = "[Reymart]: "
    print(paint(label, CYAN), end="", flush=True)
    try:
        with Thinking(label=label, label_color=CYAN):
            reply = client.ask(prompt)
    except KeyboardInterrupt:
        print(paint("(cancelled)", DIM))
        return None
    if animate_output:
        animate(reply)
    else:
        print(reply)
    print()
    return reply


def save_session(history, model):
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    path = SESSION_DIR / f"{stamp}.json"
    try:
        SESSION_DIR.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"model": model, "turns": history}, indent=2))
    except OSError as err:
        raise RuntimeError(f"cannot write to {path}: {err}") from err
    return path


def load_session(name):
    path = Path(name).expanduser()
    if not path.exists():
        path = SESSION_DIR / (name if name.endswith(".json") else f"{name}.json")
    if not path.exists():
        raise FileNotFoundError(f"no session named {name} in {SESSION_DIR}")
    return json.loads(path.read_text())


def list_sessions():
    try:
        return sorted(SESSION_DIR.glob("*.json"))
    except OSError:
        return []


HELP = """commands
  /help              show this list
  /history           print the conversation so far
  /model             show the model the endpoint is serving
  /reset             clear the conversation
  /save              write the conversation to the data folder
  /load <name>       restore a saved conversation
  /sessions          list saved conversations
  /exit              quit
  up/down            walk input history, tab completes commands
  ctrl+c             cancel the current line, press twice to quit"""

COMMANDS = [
    "/help",
    "/history",
    "/model",
    "/reset",
    "/clear",
    "/save",
    "/load",
    "/sessions",
    "/exit",
    "/quit",
]


class Prompt:
    def __init__(self, label="[You]: "):
        self.label = label
        self.message = paint(label, GREEN)
        self.frontend = "plain"
        self.session = None
        self.readline = None
        if not sys.stdin.isatty():
            return

        try:
            from prompt_toolkit import PromptSession
            from prompt_toolkit.completion import WordCompleter
            from prompt_toolkit.formatted_text import FormattedText
            from prompt_toolkit.history import FileHistory

            self.session = PromptSession(
                history=FileHistory(str(HISTORY_FILE)),
                completer=WordCompleter(COMMANDS, ignore_case=True),
                complete_while_typing=False,
            )
            self.message = FormattedText([("ansigreen", label)])
            self.frontend = "prompt_toolkit"
            return
        except ImportError:
            pass

        try:
            import readline as readline_module
        except ImportError:
            try:
                import gnureadline as readline_module
            except ImportError:
                return

        self.readline = readline_module
        self.frontend = "readline"
        readline_module.parse_and_bind("tab: complete")
        readline_module.set_completer_delims(" \t\n")
        readline_module.set_completer(self._complete)
        try:
            readline_module.read_history_file(str(HISTORY_FILE))
        except (FileNotFoundError, OSError):
            pass

    def _complete(self, text, state):
        if not text.startswith("/"):
            return None
        matches = [command for command in COMMANDS if command.startswith(text)]
        return matches[state] if state < len(matches) else None

    def ask(self):
        if self.session is not None:
            return self.session.prompt(self.message)
        return input(self.message)

    def close(self):
        if self.readline is not None:
            try:
                self.readline.write_history_file(str(HISTORY_FILE))
            except OSError:
                pass


def handle_command(line, history, client):
    command, _, argument = line[1:].partition(" ")
    command = command.lower()
    argument = argument.strip()

    if command in ("exit", "quit"):
        return "quit"
    if command == "help":
        print(HELP)
    elif command == "history":
        if not history:
            print(paint("conversation is empty", DIM))
        for turn in history:
            label = "[You]: " if turn["role"] == "user" else "[Reymart]: "
            print(paint(label, GREEN if turn["role"] == "user" else CYAN) + turn["text"])
    elif command == "model":
        print(client.model or "unknown, no call made yet")
    elif command in ("reset", "clear"):
        history.clear()
        print(paint("conversation cleared", DIM))
    elif command == "save":
        try:
            print(paint(f"saved to {save_session(history, client.model)}", GREEN))
        except RuntimeError as err:
            print(paint(f"error: {err}", RED))
    elif command == "load":
        if not argument:
            print(paint("usage: /load <name>", YELLOW))
        else:
            try:
                data = load_session(argument)
            except (OSError, ValueError) as err:
                print(paint(f"error: {err}", RED))
                return None
            history[:] = data.get("turns", [])
            if data.get("model"):
                client.model = data["model"]
            print(paint(f"loaded {len(history)} turns", GREEN))
    elif command == "sessions":
        saved = list_sessions()
        print("\n".join(p.name for p in saved) or paint("no saved sessions", DIM))
    else:
        print(paint(f"unknown command: /{command}, try /help", YELLOW))
    return None


def run_once(client, question, animate_output):
    reply = reply_block(client, build_prompt([], question), animate_output)
    if reply is None:
        return 130
    return 0


def run_repl(client, animate_output):
    history = []
    prompt = Prompt()
    print(paint(f"gemini chat, a chatbot by Reymart Centeno", CYAN))
    print(paint(f"endpoint {client.endpoint}", DIM))
    print(paint(f"input: {prompt.frontend}, up/down for history, tab completes commands", DIM))
    print(paint(f"data: {DATA_DIR}", DIM))
    print(paint("type /help for commands, /exit to quit", DIM))
    print()

    while True:
        try:
            line = prompt.ask().strip()
        except KeyboardInterrupt:
            if history or line:
                print(paint("(cleared)", DIM))
                history.clear()
                continue
            print()
            prompt.close()
            return 0
        except EOFError:
            print()
            prompt.close()
            return 0

        if not line:
            continue
        if line.startswith("/"):
            if handle_command(line, history, client) == "quit":
                prompt.close()
                return 0
            continue

        history.append({"role": "user", "text": line})
        try:
            reply = reply_block(client, build_prompt(history[:-1], line), animate_output)
        except RuntimeError as err:
            history.pop()
            print(paint(f"error: {err}", RED))
            continue
        if reply is None:
            history.pop()
            continue
        history.append({"role": "model", "text": reply})


def main(argv):
    endpoint = os.environ.get("GEMINI_ENDPOINT", DEFAULT_ENDPOINT)
    args = list(argv)
    animate_output = True
    assume_yes = False
    assume_no = False
    data_dir = None
    portable = False
    while args and args[0].startswith("--"):
        flag = args.pop(0)
        if flag in ("--url", "--endpoint"):
            endpoint = args.pop(0) if args else endpoint
        elif flag == "--no-animate":
            animate_output = False
        elif flag == "--install":
            assume_yes = True
        elif flag == "--no-install":
            assume_no = True
        elif flag == "--data-dir":
            data_dir = args.pop(0) if args else None
        elif flag == "--portable":
            portable = True
        elif flag in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            print(f"unknown flag: {flag}", file=sys.stderr)
            return 2

    configure_data_dir(override=data_dir, portable=portable)

    if assume_yes or assume_no:
        ensure_requirements(assume_yes=assume_yes, assume_no=assume_no)

    client = GeminiClient(endpoint)
    if args:
        question = " ".join(args)
        try:
            return run_once(client, question, animate_output)
        except RuntimeError as err:
            print(paint(f"error: {err}", RED), file=sys.stderr)
            return 1
    ensure_requirements(assume_yes=assume_yes, assume_no=assume_no)
    return run_repl(client, animate_output)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
