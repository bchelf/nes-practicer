"""NES-style keyboard timing trainer - web/WASM build.

Adapted from timing_practice.py to run under pygbag (Pyodide + pygame).
"""

from __future__ import annotations

import asyncio
import io
import math
import wave
from array import array
from collections import deque
from dataclasses import dataclass
from time import perf_counter

import pygame


FPS = 60
FRAME_SECONDS = 1.0 / FPS
WINDOW_SIZE = (900, 620)
MAX_HISTORY = 10
SAMPLE_RATE = 44_100

BUTTONS = {
    pygame.K_w: "Up",
    pygame.K_s: "Down",
    pygame.K_a: "Left",
    pygame.K_d: "Right",
    pygame.K_k: "B",
    pygame.K_l: "A",
}

GLYPHS = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01111", "10000", "10000", "10011", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
    "6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    ",": ["00000", "00000", "00000", "00000", "01100", "00100", "01000"],
    ":": ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    "=": ["00000", "00000", "11111", "00000", "11111", "00000", "00000"],
    "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
    ">": ["10000", "01000", "00100", "00010", "00100", "01000", "10000"],
    "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
    "(": ["00010", "00100", "01000", "01000", "01000", "00100", "00010"],
    ")": ["01000", "00100", "00010", "00010", "00010", "00100", "01000"],
    "_": ["00000", "00000", "00000", "00000", "00000", "00000", "11111"],
    "?": ["01110", "10001", "00001", "00010", "00100", "00000", "00100"],
}


class BitmapFont:
    def __init__(self, scale: int, bold: bool = False) -> None:
        self.scale = scale
        self.bold = bold

    def render(self, text, antialias, color):
        del antialias
        text = text.upper()
        width = max(1, len(text) * 6 * self.scale - self.scale)
        height = 7 * self.scale
        surface = pygame.Surface((width, height), pygame.SRCALPHA)
        draw_width = 2 if self.bold and self.scale >= 3 else 1

        for char_index, char in enumerate(text):
            glyph = GLYPHS.get(char, GLYPHS["?"])
            offset_x = char_index * 6 * self.scale
            for row_index, row in enumerate(glyph):
                for col_index, pixel in enumerate(row):
                    if pixel != "1":
                        continue
                    rect = pygame.Rect(
                        offset_x + col_index * self.scale,
                        row_index * self.scale,
                        self.scale + draw_width - 1,
                        self.scale,
                    )
                    pygame.draw.rect(surface, color, rect)
        return surface


class SuccessSound:
    def __init__(self) -> None:
        self.sound = None
        self._raw = None
        self._tried = False

    def _ensure(self) -> None:
        if self._tried:
            return
        self._tried = True
        try:
            pygame.mixer.init(SAMPLE_RATE, -16, 1, 512)
        except Exception:
            return
        try:
            self._raw = self._build_wav_buffer()
            self.sound = pygame.mixer.Sound(buffer=self._raw)
        except Exception:
            self.sound = None

    def play(self) -> None:
        self._ensure()
        if self.sound is not None:
            try:
                self.sound.play()
            except Exception:
                pass

    @property
    def visual_sync_delay(self) -> float:
        return 0.0

    @staticmethod
    def _build_wav_buffer() -> bytes:
        notes = (523.25, 659.25, 783.99, 1046.50, 1318.51, 1567.98)
        note_seconds = 0.075
        gap_seconds = 0.006
        samples = array("h")

        for frequency in notes:
            note_count = int(SAMPLE_RATE * note_seconds)
            gap_count = int(SAMPLE_RATE * gap_seconds)
            for index in range(note_count):
                t = index / SAMPLE_RATE
                fade_in = min(1.0, index / (SAMPLE_RATE * 0.006))
                fade_out = min(1.0, (note_count - index) / (SAMPLE_RATE * 0.018))
                envelope = min(fade_in, fade_out)
                value = math.sin(2.0 * math.pi * frequency * t)
                samples.append(int(value * envelope * 13_000))
            samples.extend([0] * gap_count)

        return samples.tobytes()


class Firework:
    def __init__(self) -> None:
        self.started_at = -10.0
        self.duration = 0.75
        self.center = (WINDOW_SIZE[0] // 2, WINDOW_SIZE[1] // 2)
        self.angles = [math.tau * index / 16 for index in range(16)]

    def trigger(self, now: float) -> None:
        self.started_at = now

    def reset(self) -> None:
        self.started_at = -10.0

    def draw(self, surface, now: float) -> None:
        elapsed = now - self.started_at
        if elapsed < 0 or elapsed > self.duration:
            return

        progress = elapsed / self.duration
        radius = 18 + self._ease_out(progress) * 520
        star_size = max(5, int(16 - progress * 8))
        alpha = max(0, min(255, int((1.0 - progress) * 255)))
        colors = (
            (120, 255, 172, alpha),
            (255, 233, 130, alpha),
            (132, 210, 255, alpha),
        )
        layer = pygame.Surface(WINDOW_SIZE, pygame.SRCALPHA)

        cx, cy = self.center
        for index, angle in enumerate(self.angles):
            x = cx + math.cos(angle) * radius
            y = cy + math.sin(angle) * radius
            self._draw_star(layer, (x, y), star_size, colors[index % len(colors)])

        surface.blit(layer, (0, 0))

    @staticmethod
    def _ease_out(value: float) -> float:
        return 1.0 - (1.0 - value) ** 3

    @staticmethod
    def _draw_star(surface, center, radius, color):
        cx, cy = center
        points = []
        for index in range(10):
            angle = -math.pi / 2 + index * math.pi / 5
            point_radius = radius if index % 2 == 0 else radius * 0.42
            points.append((cx + math.cos(angle) * point_radius,
                           cy + math.sin(angle) * point_radius))
        pygame.draw.polygon(surface, color, points)


@dataclass(frozen=True)
class Attempt:
    start_button: str
    end_button: str
    frames: int
    seconds: float
    goal_frames: int

    @property
    def result(self) -> str:
        if self.frames < self.goal_frames:
            return "Early"
        if self.frames > self.goal_frames:
            return "Late"
        return "On target"


def draw_text(surface, font, text, pos, color=(232, 236, 241)):
    image = font.render(text, True, color)
    return surface.blit(image, pos)


def draw_panel(surface, rect, fill, border=(65, 72, 84)):
    pygame.draw.rect(surface, fill, rect, border_radius=8)
    pygame.draw.rect(surface, border, rect, width=1, border_radius=8)


def summarize(history):
    early = sum(1 for item in history if item.result == "Early")
    on_target = sum(1 for item in history if item.result == "On target")
    late = sum(1 for item in history if item.result == "Late")
    return early, on_target, late


async def main() -> None:
    pygame.display.init()
    pygame.font.init()
    pygame.display.set_caption("NES Timing Practice")
    screen = pygame.display.set_mode(WINDOW_SIZE)
    success_sound = SuccessSound()
    firework = Firework()

    title_font = BitmapFont(4, bold=True)
    big_font = BitmapFont(7, bold=True)
    goal_font = BitmapFont(5, bold=True)
    font = BitmapFont(2)
    small_font = BitmapFont(2)
    history_font = BitmapFont(1)

    goal_text = "3"
    goal_frames = int(goal_text)
    history: deque = deque(maxlen=MAX_HISTORY)
    last_attempt = None
    current_streak = 0
    best_streak = 0

    waiting_start = True
    start_button = None
    start_time = 0.0
    live_frames = 0
    message = "Press W/S/A/D/K/L to start."
    goal_active = False

    running = True
    while running:
        now = perf_counter()

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
                continue

            if event.type != pygame.KEYDOWN:
                continue

            if event.key == pygame.K_ESCAPE:
                running = False
                continue

            if event.key == pygame.K_r:
                waiting_start = True
                start_button = None
                live_frames = 0
                last_attempt = None
                current_streak = 0
                best_streak = 0
                firework.reset()
                history.clear()
                message = "Reset. Press a mapped key to start."
                continue

            if event.key == pygame.K_g:
                goal_active = True
                message = "Editing goal frames. Type a number and press Enter."
                continue

            if goal_active:
                if event.key in (pygame.K_RETURN, pygame.K_KP_ENTER):
                    goal_frames = max(0, int(goal_text or "0"))
                    history.clear()
                    last_attempt = None
                    current_streak = 0
                    best_streak = 0
                    firework.reset()
                    goal_active = False
                    message = f"Goal set to {goal_frames} frame(s). History cleared."
                elif event.key == pygame.K_BACKSPACE:
                    goal_text = goal_text[:-1]
                elif event.unicode.isdigit() and len(goal_text) < 4:
                    goal_text += event.unicode
                continue

            if event.key not in BUTTONS:
                continue

            button = BUTTONS[event.key]
            if waiting_start:
                waiting_start = False
                start_button = button
                start_time = now
                live_frames = 0
                message = f"Started with {button}. Press any mapped key to stop."
            else:
                elapsed = max(0.0, now - start_time)
                frames = int(elapsed / FRAME_SECONDS)
                last_attempt = Attempt(
                    start_button=start_button or "?",
                    end_button=button,
                    frames=frames,
                    seconds=elapsed,
                    goal_frames=goal_frames,
                )
                history.append(last_attempt)
                if last_attempt.result == "On target":
                    current_streak += 1
                    best_streak = max(best_streak, current_streak)
                else:
                    current_streak = 0
                waiting_start = True
                start_button = None
                live_frames = 0
                delta = frames - goal_frames
                if delta == 0:
                    message = "On target."
                    success_sound.play()
                    firework.trigger(now + success_sound.visual_sync_delay)
                elif delta < 0:
                    message = f"Early by {-delta} frame(s)."
                else:
                    message = f"Late by {delta} frame(s)."

        if not waiting_start:
            live_frames = int((perf_counter() - start_time) / FRAME_SECONDS)

        screen.fill((18, 21, 27))

        draw_text(screen, title_font, "NES Timing Practice", (32, 24))
        draw_text(screen, small_font,
                  "Mapped keys: W Up  S Down  A Left  D Right  K B  L A",
                  (34, 70), (166, 176, 190))
        draw_text(screen, small_font,
                  "G edit goal   R reset   Esc quit",
                  (34, 96), (166, 176, 190))

        draw_panel(screen, pygame.Rect(32, 134, 400, 185), (26, 31, 39))
        draw_text(screen, font, "Current Timer", (56, 158), (166, 176, 190))
        timer_text = f"{live_frames} frame{'s' if live_frames != 1 else ''}"
        draw_text(screen, big_font, timer_text, (56, 192), (245, 247, 250))
        status = "Waiting for first press" if waiting_start else f"Started: {start_button}"
        draw_text(screen, font, status, (58, 270), (120, 202, 168))

        draw_panel(screen, pygame.Rect(468, 134, 400, 185), (26, 31, 39))
        draw_text(screen, font, "Goal", (492, 158), (166, 176, 190))
        goal_color = (255, 209, 102) if goal_active else (245, 247, 250)
        cursor = "_" if goal_active else ""
        shown_goal = goal_text if goal_active else str(goal_frames)
        draw_text(screen, goal_font, f"{shown_goal}{cursor}", (492, 198), goal_color)
        draw_text(screen, font, "frames at 60 Hz", (496, 270), (166, 176, 190))

        draw_panel(screen, pygame.Rect(32, 350, 400, 220), (26, 31, 39))
        draw_text(screen, font, "Last Report", (56, 374), (166, 176, 190))
        if last_attempt is None:
            draw_text(screen, font, "No attempt yet.", (56, 420), (245, 247, 250))
        else:
            result_color = {
                "Early": (94, 197, 255),
                "On target": (120, 202, 168),
                "Late": (255, 117, 117),
            }[last_attempt.result]
            draw_text(screen, font,
                      f"{last_attempt.start_button} -> {last_attempt.end_button}",
                      (56, 416))
            draw_text(screen, font,
                      f"{last_attempt.frames} frame(s)  ({last_attempt.seconds:.4f}s raw)",
                      (56, 452))
            draw_text(screen, font, last_attempt.result, (56, 488), result_color)

        draw_panel(screen, pygame.Rect(468, 350, 400, 220), (26, 31, 39))
        draw_text(screen, font, f"Last {MAX_HISTORY} Attempts", (492, 374), (166, 176, 190))
        early, on_target, late = summarize(history)
        draw_text(screen, font,
                  f"Early {early}   On {on_target}   Late {late}",
                  (492, 414), (245, 247, 250))
        y = 444
        for index, item in enumerate(reversed(history), start=1):
            result_marker = {"Early": "-", "On target": "=", "Late": "+"}[item.result]
            line = (f"{index:2}. {item.start_button:>5} -> {item.end_button:<5} "
                    f"{item.frames:>3}f  {result_marker}")
            draw_text(screen, history_font, line, (492, y), (205, 211, 220))
            y += 12

        draw_text(screen, small_font,
                  f"On-target streak {current_streak}   Best {best_streak}",
                  (492, 576), (120, 202, 168))
        draw_text(screen, small_font, message, (34, 596), (255, 209, 102))
        firework.draw(screen, perf_counter())

        pygame.display.flip()
        await asyncio.sleep(1.0 / FPS)

    pygame.quit()


asyncio.run(main())
