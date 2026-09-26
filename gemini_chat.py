#!/usr/bin/env python3
"""Terminal chatbot for the worker8651 Gemini endpoint.

Usage:
    python3 gemini_chat.py
    python3 gemini_chat.py "explain rust ownership in two sentences"
    python3 gemini_chat.py --url http://localhost:8787/api/groovyrey/gemini
    python3 gemini_chat.py --install          accept the dependency install prompt
    python3 gemini_chat.py --no-install       never install, always fall back
    python3 gemini_chat.py --ui spa            full screen app view
    python3 gemini_chat.py --data-dir ./data keep history next to this file
    python3 gemini_chat.py --portable         force a .gemini_chat folder here

Portable use: copy gemini_chat.py to a flash drive and run it with any Python
3.8 or newer on that machine. Sessions and input history live in a
.gemini_chat folder next to the script when the script sits on removable media
and that folder is writable, otherwise they fall back to the home directory.
Read-only media is detected, nothing is written and the chat still runs.

Two views: the default chat view appends to the scrollback, and --ui spa takes
over the whole screen and repaints a frame on every state change (alt screen,
raw key input, spinner in the status line, replies revealed as they arrive).

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
import shutil
import subprocess
import sys
import textwrap
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


class KeyReader:
    """Reads single keypresses with a timeout so the frame loop never blocks."""

    SPECIAL = {
        b"\r": "ENTER",
        b"\n": "ENTER",
        b"\x7f": "BACKSPACE",
        b"\x08": "BACKSPACE",
        b"\x03": "CTRLC",
        b"\x04": "CTRLD",
        b"\x15": "CTRLU",
        b"\x17": "CTRLW",
        b"\x0b": "CTRLK",
        b"\x01": "CTRLA",
        b"\x05": "CTRLE",
        b"\t": "TAB",
    }
    SEQUENCES = {
        b"\x1b[A": "UP",
        b"\x1b[B": "DOWN",
        b"\x1b[C": "RIGHT",
        b"\x1b[D": "LEFT",
        b"\x1bOA": "UP",
        b"\x1bOB": "DOWN",
        b"\x1bOC": "RIGHT",
        b"\x1bOD": "LEFT",
        b"\x1b[H": "HOME",
        b"\x1b[F": "END",
        b"\x1b[1~": "HOME",
        b"\x1b[4~": "END",
        b"\x1b[3~": "DEL",
        b"\x1b[5~": "PGUP",
        b"\x1b[6~": "PGDN",
    }

    def __init__(self):
        self.pending = b""
        self.saved = None
        self.fd = None
        self.termios = None
        self.ok = False
        self.windows = os.name == "nt"

    def _apply(self, mode):
        for when in (self.termios.TCSADRAIN, self.termios.TCSANOW):
            try:
                self.termios.tcsetattr(self.fd, when, mode)
                return True
            except self.termios.error:
                continue
        return False

    def __enter__(self):
        self.ok = True
        if self.windows:
            return self
        try:
            import termios
        except ImportError:
            self.ok = False
            return self

        self.termios = termios
        self.fd = sys.stdin.fileno()
        try:
            self.saved = termios.tcgetattr(self.fd)
            mode = termios.tcgetattr(self.fd)
            mode[3] &= ~(termios.ICANON | termios.ECHO | termios.ISIG)
            mode[6][termios.VMIN] = 0
            mode[6][termios.VTIME] = 0
            self.ok = self._apply(mode)
        except (termios.error, ValueError, OSError):
            self.ok = False
        return self

    def __exit__(self, *exc):
        if self.saved is not None and self.fd is not None:
            self._apply(self.saved)
        return False

    def _pull(self, timeout):
        if self.windows:
            import msvcrt

            deadline = time.monotonic() + timeout
            while True:
                if msvcrt.kbhit():
                    char = msvcrt.getwch()
                    if char in ("\x00", "\xe0"):
                        code = msvcrt.getwch()
                        return {"H": b"\x1b[A", "P": b"\x1b[B", "K": b"\x1b[D", "M": b"\x1b[C"}.get(code, b"").encode()
                    return char.encode("utf-8", "replace")
                if time.monotonic() >= deadline:
                    return b""
                time.sleep(0.01)
        import select

        ready, _, _ = select.select([sys.stdin], [], [], timeout)
        if not ready:
            return b""
        return os.read(self.fd, 4096)

    def _next_key(self):
        while self.pending:
            if self.pending.startswith(b"\x1b"):
                for sequence, name in self.SEQUENCES.items():
                    if self.pending.startswith(sequence):
                        self.pending = self.pending[len(sequence) :]
                        return name
                if self.pending == b"\x1b":
                    return None
                if len(self.pending) < 3 and self.pending[:2] in (b"\x1b[", b"\x1bO"):
                    return None
                self.pending = self.pending[1:]
                continue
            lead = self.pending[0]
            if lead < 0x80:
                size = 1
            elif lead >= 0xF0:
                size = 4
            elif lead >= 0xE0:
                size = 3
            elif lead >= 0xC0:
                size = 2
            else:
                self.pending = self.pending[1:]
                continue
            if len(self.pending) < size:
                return None
            chunk, self.pending = self.pending[:size], self.pending[size:]
            name = self.SPECIAL.get(chunk)
            if name:
                return name
            text = chunk.decode("utf-8", "replace")
            if text.isprintable() or text == " ":
                return text
        return None

    def read_key(self, timeout):
        data = self._pull(timeout)
        if data:
            self.pending += data
        return self._next_key()


class LineEditor:
    def __init__(self, commands):
        self.text = ""
        self.cursor = 0
        self.history = []
        self.index = 0
        self.stash = ""
        self.commands = commands

    def clear(self):
        self.text = ""
        self.cursor = 0
        self.index = len(self.history)

    def _word_left(self):
        position = self.cursor
        while position > 0 and self.text[position - 1] == " ":
            position -= 1
        while position > 0 and self.text[position - 1] != " ":
            position -= 1
        return position

    def _complete(self):
        head = self.text[: self.cursor]
        start = head.rfind(" ") + 1
        token = head[start:]
        if not token.startswith("/"):
            return
        matches = [command for command in self.commands if command.startswith(token)]
        if not matches:
            return
        if len(matches) == 1:
            self.text = self.text[:start] + matches[0] + self.text[self.cursor :]
            self.cursor = start + len(matches[0])
            return
        shared = os.path.commonprefix(matches)
        if len(shared) > len(token):
            self.text = self.text[:start] + shared + self.text[self.cursor :]
            self.cursor = start + len(shared)
        else:
            self.matches = matches

    def key(self, name):
        if name in ("ENTER",):
            line = self.text.strip()
            if line:
                if not self.history or self.history[-1] != line:
                    self.history.append(line)
            self.clear()
            return "submit", line
        if name == "CTRLC":
            if self.text:
                self.clear()
                return "cleared", ""
            return "quit", ""
        if name == "CTRLD":
            return ("quit", "") if not self.text else ("none", "")
        if name == "BACKSPACE":
            if self.cursor:
                self.text = self.text[: self.cursor - 1] + self.text[self.cursor :]
                self.cursor -= 1
        elif name == "DEL":
            self.text = self.text[: self.cursor] + self.text[self.cursor + 1 :]
        elif name == "LEFT":
            self.cursor = max(0, self.cursor - 1)
        elif name == "RIGHT":
            self.cursor = min(len(self.text), self.cursor + 1)
        elif name == "HOME":
            self.cursor = 0
        elif name == "END":
            self.cursor = len(self.text)
        elif name == "UP":
            if self.index > 0:
                if self.index == len(self.history):
                    self.stash = self.text
                self.index -= 1
                self.text = self.history[self.index]
                self.cursor = len(self.text)
        elif name == "DOWN":
            if self.index < len(self.history):
                self.index += 1
                self.text = self.history[self.index] if self.index < len(self.history) else self.stash
                self.cursor = len(self.text)
        elif name == "CTRLU":
            self.text = self.text[self.cursor :]
            self.cursor = 0
        elif name == "CTRLK":
            self.text = self.text[: self.cursor]
        elif name == "CTRLW":
            position = self._word_left()
            self.text = self.text[:position] + self.text[self.cursor :]
            self.cursor = position
        elif name == "TAB":
            self._complete()
        elif name and len(name) == 1:
            self.text = self.text[: self.cursor] + name + self.text[self.cursor :]
            self.cursor += 1
        return "none", ""


class Screen:
    def __init__(self):
        self.active = sys.stdout.isatty() and sys.stdin.isatty()

    def __enter__(self):
        if self.active:
            sys.stdout.write("\033[?1049h\033[?25l\033[2J\033[H")
            sys.stdout.flush()
        return self

    def __exit__(self, *exc):
        if self.active:
            sys.stdout.write("\033[?25h\033[0m\033[?1049l")
            sys.stdout.flush()
        return False

    def paint_frame(self, frame, cursor_row, cursor_col):
        out = ["\033[?25l\033[H"]
        limit = min(len(frame), cursor_row)
        for row, segments in enumerate(frame[:limit], start=1):
            text = "".join(paint(part, color) if color else part for part, color in segments)
            out.append(f"\033[{row};1H\033[K{text}")
        for row in range(limit + 1, cursor_row + 1):
            out.append(f"\033[{row};1H\033[K")
        out.append(f"\033[{cursor_row};{max(1, cursor_col)}H\033[?25h")
        sys.stdout.write("".join(out))
        sys.stdout.flush()


class SpaApp:
    IDLE_HINT = "ctrl+c clears the line, tab completes commands, /help lists everything"

    def __init__(self, client):
        self.client = client
        self.turns = []
        self.editor = LineEditor(COMMANDS)
        self.reader = KeyReader()
        self.screen = Screen()
        self.busy = False
        self.typing = None
        self.typing_started = 0.0
        self.typing_duration = 1.0
        self.revealed = 0
        self.result = None
        self.error = None
        self.worker = None
        self.started = 0.0
        self.notice = None
        self.notice_until = 0.0
        self.quit = False

    def say(self, text, color=DIM, seconds=4.0):
        self.notice = (text, color)
        self.notice_until = time.monotonic() + seconds

    def _ask_worker(self, prompt):
        try:
            self.result = self.client.ask(prompt)
        except RuntimeError as err:
            self.error = str(err)
        except Exception as err:
            self.error = f"unexpected error: {err}"

    def submit(self, line):
        if line.startswith("/"):
            self.spa_command(line)
            return
        self.turns.append({"role": "user", "text": line})
        self.busy = True
        self.started = time.monotonic()
        self.result = None
        self.error = None
        self.worker = threading.Thread(target=self._ask_worker, args=(build_prompt(self.turns[:-1], line),), daemon=True)
        self.worker.start()

    def _finish_turn(self):
        self.busy = False
        if self.error:
            self.turns.pop()
            self.say(f"error: {self.error}", RED, 8.0)
            self.error = None
            return
        reply = (self.result or "").strip()
        if not reply:
            self.turns.pop()
            self.say("the endpoint returned an empty answer", YELLOW, 6.0)
            return
        self.typing = reply
        self.typing_started = time.monotonic()
        self.typing_duration = min(1.6, max(0.25, len(reply) / 220))
        self.revealed = 0

    def _tick(self):
        if self.busy and self.worker is not None and not self.worker.is_alive():
            self._finish_turn()
        if self.typing is not None:
            progress = min(1.0, (time.monotonic() - self.typing_started) / self.typing_duration)
            self.revealed = int(len(self.typing) * progress)
            if progress >= 1.0:
                self.turns.append({"role": "model", "text": self.typing})
                self.typing = None
        if self.notice and time.monotonic() > self.notice_until:
            self.notice = None

    def spa_command(self, line):
        command, _, argument = line[1:].partition(" ")
        command = command.lower()
        argument = argument.strip()
        if command in ("exit", "quit"):
            self.quit = True
        elif command == "help":
            self.say(HELP.replace("\n", "   "), DIM, 12.0)
        elif command == "history":
            self.say(f"{len(self.turns)} turns on screen, newest at the bottom", DIM)
        elif command == "model":
            self.say(self.client.model or "no call made yet", DIM)
        elif command in ("reset", "clear"):
            self.turns.clear()
            self.say("conversation cleared", DIM)
        elif command == "save":
            try:
                self.say(f"saved to {save_session(self.turns, self.client.model)}", GREEN)
            except RuntimeError as err:
                self.say(f"error: {err}", RED, 8.0)
        elif command == "load":
            if not argument:
                self.say("usage: /load <name>", YELLOW)
            else:
                try:
                    data = load_session(argument)
                except (OSError, ValueError) as err:
                    self.say(f"error: {err}", RED, 8.0)
                    return
                self.turns = list(data.get("turns", []))
                if data.get("model"):
                    self.client.model = data["model"]
                self.say(f"loaded {len(self.turns)} turns", GREEN)
        elif command == "sessions":
            saved = [path.name for path in list_sessions()]
            self.say(", ".join(saved) if saved else "no saved sessions", DIM, 10.0)
        else:
            self.say(f"unknown command: /{command}, try /help", YELLOW)

    def _body(self, rows, width):
        lines = []
        for turn in self.turns:
            user = turn["role"] == "user"
            label = "[You]: " if user else "[Reymart]: "
            color = GREEN if user else CYAN
            text = turn["text"]
            if self.typing is not None and not user:
                text = text[: self.revealed]
            wrapped = textwrap.wrap(text, max(20, width - len(label))) or [""]
            lines.append([(label, color), (wrapped[0], None)])
            for extra in wrapped[1:]:
                lines.append([(" " * len(label), None), (extra, None)])
            lines.append([])
        lines.append([])
        while len(lines) < rows:
            lines.insert(0, [])
        return lines[-rows:] if len(lines) > rows else lines

    def _status(self):
        segments = []
        if self.busy:
            elapsed = time.monotonic() - self.started
            frame = SPINNER[int(elapsed * 12) % len(SPINNER)]
            segments.append((f"{frame} thinking {elapsed:4.1f}s", DIM))
        elif self.typing is not None:
            segments.append(("receiving", DIM))
        if self.notice:
            text, color = self.notice
            if segments:
                segments.append(("   ", DIM))
            segments.append((text, color))
        return segments or [(self.IDLE_HINT, DIM)]

    def _input_row(self, text, cursor, width):
        room = max(10, width - len("[You]: "))
        start = 0
        if cursor >= room:
            start = cursor - room + 1
        window = text[start : start + room]
        return window, len("[You]: ") + cursor - start

    def frame(self):
        width, height = shutil.get_terminal_size(fallback=(80, 24))
        width = max(32, width)
        height = max(8, height)
        rows = max(1, height - 6)
        frame = [
            [("gemini chat, a chatbot by Reymart Centeno", CYAN)],
            [(f"endpoint {self.client.endpoint}", DIM)],
            [(f"model {self.client.model or 'unknown'}   data {DATA_DIR}", DIM)],
            [],
        ]
        frame.extend(self._body(rows, width))
        frame.append(self._status())
        window, column = self._input_row(self.editor.text, self.editor.cursor, width)
        frame.append([("[You]: ", GREEN), (window, None)])
        return frame, height, column

    def run(self):
        with self.screen:
            with self.reader:
                if not self.reader.ok:
                    raise OSError("the terminal refused raw key input")
                while not self.quit:
                    frame, height, column = self.frame()
                    self.screen.paint_frame(frame, height, column)
                    key = self.reader.read_key(0.08)
                    if key is None:
                        self._tick()
                        continue
                    if self.busy:
                        if key == "ENTER":
                            self.say("still waiting for the previous answer", YELLOW, 3.0)
                            continue
                        if key == "CTRLC":
                            self.editor.key("CTRLC")
                            self.say("the request still finishes in the background", YELLOW, 5.0)
                            continue
                        self.editor.key(key)
                        continue
                    action, line = self.editor.key(key)
                    if action == "submit":
                        self.submit(line)
                    elif action == "cleared":
                        self.say("line cleared", DIM, 1.5)
                    elif action == "quit":
                        self.quit = True
        return 0


def run_spa(client):
    if not (sys.stdout.isatty() and sys.stdin.isatty()):
        print(paint("the spa view needs a real terminal, falling back to the chat view", YELLOW))
        return run_repl(client, True)
    if os.name != "nt":
        try:
            import termios
        except ImportError:
            print(paint("this python has no termios, falling back to the chat view", YELLOW))
            return run_repl(client, True)
    app = SpaApp(client)
    try:
        return app.run()
    except Exception as err:
        print(paint(f"the spa view stopped ({err}), falling back to the chat view", YELLOW))
        return run_repl(client, True)


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
    mode = "chat"
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
        elif flag in ("--ui", "--render"):
            mode = (args.pop(0) if args else "chat").lower()
            if mode not in ("chat", "spa"):
                print(f"unknown ui: {mode}, use chat or spa", file=sys.stderr)
                return 2
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
    if mode == "spa":
        return run_spa(client)
    ensure_requirements(assume_yes=assume_yes, assume_no=assume_no)
    return run_repl(client, animate_output)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
