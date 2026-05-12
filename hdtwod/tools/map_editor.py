#!/usr/bin/env python3
"""
Hex map editor — produces JSON in the format consumed by HexBoard3D.

Controls
--------
Left-click          : paint selected terrain on a hex (creates if absent)
Ctrl + left-click   : raise elevation of hex under cursor (+1, wraps 0-8)
Right-click         : erase hex
Middle-drag / drag  : pan the viewport
Scroll wheel        : zoom

Toolbar buttons
---------------
Terrain buttons     : select active terrain type
Erase               : switch to erase mode
Ramp                : switch to ramp-edge mode
                        (click an edge to toggle its ramp flag)
Save                : write / overwrite the JSON file
Load                : read an existing JSON file

Ramp-edge mode
--------------
Click near the midpoint of any painted hex edge to toggle that edge's ramp flag.
Ramp edges are drawn as a dashed orange line.

Directions (matches GDScript HexCoord):
  0=E  1=NE  2=NW  3=W  4=SW  5=SE
"""

import json
import math
import os
import sys
import tkinter as tk
from tkinter import filedialog, messagebox

# ---------------------------------------------------------------------------
# Hex geometry (pointy-top, axial coordinates)
# ---------------------------------------------------------------------------
HEX_SIZE = 40          # pixels, radius corner-to-center
SQRT3 = math.sqrt(3)

TERRAIN_COLORS = {
    "grass": "#4a8c3f",
    "dirt":  "#8b6340",
    "water": "#2a5fa8",
}
TERRAIN_ORDER = list(TERRAIN_COLORS.keys())
DEFAULT_TERRAIN = TERRAIN_ORDER[0]

# Direction vectors (q, r) for E NE NW W SW SE
DIRECTIONS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]

MAX_ELEVATION = 8


def hex_to_pixel(q, r, size, origin):
    """Pointy-top axial → pixel centre."""
    x = size * (SQRT3 * q + SQRT3 / 2 * r)
    y = size * (3 / 2 * r)
    return x + origin[0], y + origin[1]


def pixel_to_hex_float(px, py, size, origin):
    px -= origin[0]
    py -= origin[1]
    q = (SQRT3 / 3 * px - 1 / 3 * py) / size
    r = (2 / 3 * py) / size
    return q, r


def hex_round(q, r):
    """Axial → nearest hex (cube rounding)."""
    s = -q - r
    rq, rr, rs = round(q), round(r), round(s)
    dq = abs(rq - q)
    dr = abs(rr - r)
    ds = abs(rs - s)
    if dq > dr and dq > ds:
        rq = -rr - rs
    elif dr > ds:
        rr = -rq - rs
    return int(rq), int(rr)


def hex_corners(cx, cy, size):
    """6 pixel corners of a pointy-top hex centred at (cx, cy)."""
    pts = []
    for i in range(6):
        angle = math.radians(60 * i - 30)
        pts.append((cx + size * math.cos(angle), cy + size * math.sin(angle)))
    return pts


def edge_midpoint(corners, edge_i):
    """Midpoint of the edge between corners[edge_i] and corners[(edge_i+1)%6]."""
    a = corners[edge_i]
    b = corners[(edge_i + 1) % 6]
    return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)


# ---------------------------------------------------------------------------
# Editor state
# ---------------------------------------------------------------------------
class MapEditor:
    def __init__(self, root):
        self.root = root
        root.title("Hex Map Editor")

        self.tiles = {}          # (q,r) → {"elevation":int, "terrain_type":str, "ramp_edges":[bool*6]}
        self.mode = "paint"      # "paint" | "erase" | "ramp"
        self.active_terrain = DEFAULT_TERRAIN
        self.filepath = None

        # View state
        self.origin = [600, 400]
        self.zoom = 1.0
        self._pan_start = None

        self._build_ui(root)
        self._redraw()

    # ------------------------------------------------------------------
    # UI layout
    # ------------------------------------------------------------------
    def _build_ui(self, root):
        root.columnconfigure(0, weight=1)
        root.rowconfigure(1, weight=1)

        # --- Toolbar ---
        tb = tk.Frame(root, bg="#2b2b2b", pady=4)
        tb.grid(row=0, column=0, sticky="ew")

        self.mode_buttons = {}
        self.terrain_buttons = {}

        tk.Label(tb, text="Terrain:", bg="#2b2b2b", fg="white").pack(side=tk.LEFT, padx=(8, 2))
        for name in TERRAIN_ORDER:
            color = TERRAIN_COLORS[name]
            btn = tk.Button(
                tb, text=name.capitalize(), bg=color, fg="white",
                relief=tk.SUNKEN if name == self.active_terrain else tk.RAISED,
                command=lambda n=name: self._select_terrain(n),
                width=7,
            )
            btn.pack(side=tk.LEFT, padx=2)
            self.terrain_buttons[name] = btn

        tk.Frame(tb, bg="#555", width=2).pack(side=tk.LEFT, padx=6, fill=tk.Y)

        for label, mode in [("Erase", "erase"), ("Ramps", "ramp")]:
            btn = tk.Button(
                tb, text=label, bg="#444", fg="white",
                relief=tk.RAISED,
                command=lambda m=mode: self._select_mode(m),
                width=7,
            )
            btn.pack(side=tk.LEFT, padx=2)
            self.mode_buttons[mode] = btn

        tk.Frame(tb, bg="#555", width=2).pack(side=tk.LEFT, padx=6, fill=tk.Y)

        tk.Button(tb, text="Load", bg="#444", fg="white", command=self._load,
                  width=6).pack(side=tk.LEFT, padx=2)
        tk.Button(tb, text="Save", bg="#336633", fg="white", command=self._save,
                  width=6).pack(side=tk.LEFT, padx=2)
        tk.Button(tb, text="Save As", bg="#336633", fg="white", command=self._save_as,
                  width=8).pack(side=tk.LEFT, padx=2)

        self.status = tk.Label(tb, text="", bg="#2b2b2b", fg="#aaa")
        self.status.pack(side=tk.RIGHT, padx=8)

        # --- Canvas ---
        self.canvas = tk.Canvas(root, bg="#1a1a2e", cursor="crosshair")
        self.canvas.grid(row=1, column=0, sticky="nsew")

        self.canvas.bind("<ButtonPress-1>",   self._on_lmb_press)
        self.canvas.bind("<ButtonPress-3>",   self._on_rmb)
        self.canvas.bind("<ButtonPress-2>",   self._on_pan_start)
        self.canvas.bind("<B2-Motion>",       self._on_pan_move)
        self.canvas.bind("<MouseWheel>",      self._on_scroll)       # Windows/macOS
        self.canvas.bind("<Button-4>",        self._on_scroll)       # Linux scroll up
        self.canvas.bind("<Button-5>",        self._on_scroll)       # Linux scroll down
        self.canvas.bind("<Motion>",          self._on_mouse_move)
        # Also allow left-drag for painting
        self.canvas.bind("<B1-Motion>",       self._on_lmb_drag)

    # ------------------------------------------------------------------
    # Mode / terrain selection
    # ------------------------------------------------------------------
    def _select_terrain(self, name):
        self.active_terrain = name
        self.mode = "paint"
        self._update_button_states()

    def _select_mode(self, mode):
        self.mode = mode
        self._update_button_states()

    def _update_button_states(self):
        for name, btn in self.terrain_buttons.items():
            is_active = (self.mode == "paint" and name == self.active_terrain)
            btn.config(relief=tk.SUNKEN if is_active else tk.RAISED)
        for mode, btn in self.mode_buttons.items():
            btn.config(relief=tk.SUNKEN if self.mode == mode else tk.RAISED)

    # ------------------------------------------------------------------
    # Canvas interaction
    # ------------------------------------------------------------------
    def _effective_size(self):
        return HEX_SIZE * self.zoom

    def _canvas_to_hex(self, cx, cy):
        size = self._effective_size()
        fq, fr = pixel_to_hex_float(cx, cy, size, self.origin)
        return hex_round(fq, fr)

    def _on_lmb_press(self, event):
        ctrl = (event.state & 0x4) != 0
        if ctrl:
            self._raise_elevation(event.x, event.y)
        elif self.mode == "ramp":
            self._toggle_ramp_edge(event.x, event.y)
        elif self.mode == "erase":
            q, r = self._canvas_to_hex(event.x, event.y)
            self.tiles.pop((q, r), None)
            self._redraw()
        else:
            self._paint(event.x, event.y)

    def _on_lmb_drag(self, event):
        if self.mode == "paint":
            self._paint(event.x, event.y)
        elif self.mode == "erase":
            q, r = self._canvas_to_hex(event.x, event.y)
            if (q, r) in self.tiles:
                self.tiles.pop((q, r))
                self._redraw()

    def _on_rmb(self, event):
        q, r = self._canvas_to_hex(event.x, event.y)
        self.tiles.pop((q, r), None)
        self._redraw()

    def _on_pan_start(self, event):
        self._pan_start = (event.x, event.y)

    def _on_pan_move(self, event):
        if self._pan_start:
            dx = event.x - self._pan_start[0]
            dy = event.y - self._pan_start[1]
            self.origin[0] += dx
            self.origin[1] += dy
            self._pan_start = (event.x, event.y)
            self._redraw()

    def _on_scroll(self, event):
        if event.num == 4 or event.delta > 0:
            factor = 1.1
        else:
            factor = 1 / 1.1
        # Zoom toward cursor
        cx, cy = event.x, event.y
        self.origin[0] = cx + (self.origin[0] - cx) * factor
        self.origin[1] = cy + (self.origin[1] - cy) * factor
        self.zoom *= factor
        self._redraw()

    def _on_mouse_move(self, event):
        q, r = self._canvas_to_hex(event.x, event.y)
        tile = self.tiles.get((q, r))
        if tile:
            self.status.config(text=f"({q},{r})  elev={tile['elevation']}  {tile['terrain_type']}")
        else:
            self.status.config(text=f"({q},{r})")

    # ------------------------------------------------------------------
    # Tile operations
    # ------------------------------------------------------------------
    def _paint(self, cx, cy):
        q, r = self._canvas_to_hex(cx, cy)
        if (q, r) not in self.tiles:
            self.tiles[(q, r)] = {
                "elevation": 0,
                "terrain_type": self.active_terrain,
                "ramp_edges": [False] * 6,
            }
        else:
            self.tiles[(q, r)]["terrain_type"] = self.active_terrain
        self._redraw()

    def _raise_elevation(self, cx, cy):
        q, r = self._canvas_to_hex(cx, cy)
        if (q, r) not in self.tiles:
            self.tiles[(q, r)] = {
                "elevation": 0,
                "terrain_type": self.active_terrain,
                "ramp_edges": [False] * 6,
            }
        tile = self.tiles[(q, r)]
        tile["elevation"] = (tile["elevation"] + 1) % (MAX_ELEVATION + 1)
        self._redraw()

    def _toggle_ramp_edge(self, cx, cy):
        """Find the nearest hex edge midpoint and toggle its ramp flag."""
        size = self._effective_size()
        best_dist = size * 0.45   # must be within 45% of hex radius
        best_coord = None
        best_edge = None

        for (q, r) in self.tiles:
            px, py = hex_to_pixel(q, r, size, self.origin)
            corners = hex_corners(px, py, size)
            for i in range(6):
                mx, my = edge_midpoint(corners, i)
                d = math.hypot(cx - mx, cy - my)
                if d < best_dist:
                    best_dist = d
                    best_coord = (q, r)
                    best_edge = i

        if best_coord is not None:
            edges = self.tiles[best_coord]["ramp_edges"]
            gdscript_edge = (6 - best_edge) % 6
            edges[gdscript_edge] = not edges[gdscript_edge]
            self._redraw()

    # ------------------------------------------------------------------
    # Drawing
    # ------------------------------------------------------------------
    def _redraw(self):
        self.canvas.delete("all")
        size = self._effective_size()

        # Draw grid ghost for reference (faint, just the visible area)
        self._draw_grid_ghost(size)

        for (q, r), tile in self.tiles.items():
            px, py = hex_to_pixel(q, r, size, self.origin)
            corners = hex_corners(px, py, size)
            flat = [c for pt in corners for c in pt]

            # Hex fill
            terrain = tile["terrain_type"]
            base_color = TERRAIN_COLORS.get(terrain, "#888888")
            elev = tile["elevation"]
            fill = self._lighten(base_color, elev / MAX_ELEVATION * 0.4)
            self.canvas.create_polygon(flat, fill=fill, outline="#000000", width=1)

            # Elevation label
            if elev > 0:
                self.canvas.create_text(
                    px, py, text=str(elev),
                    fill="white", font=("Consolas", max(8, int(size * 0.35)), "bold"),
                )

            # Terrain initial (small, top of hex)
            initial = terrain[0].upper()
            self.canvas.create_text(
                px, py + size * 0.25, text=initial,
                fill="white", font=("Consolas", max(6, int(size * 0.22))),
            )

            # Ramp edges
            for d, is_ramp in enumerate(tile["ramp_edges"]):
                if is_ramp:
                    geom_i = (6 - d) % 6
                    a = corners[geom_i]
                    b = corners[(geom_i + 1) % 6]
                    self.canvas.create_line(
                        a[0], a[1], b[0], b[1],
                        fill="#ff8800", width=max(2, int(size * 0.06)),
                        dash=(4, 3),
                    )

    def _draw_grid_ghost(self, size):
        """Draw faint hex outlines for nearby empty cells."""
        w = self.canvas.winfo_width() or 1200
        h = self.canvas.winfo_height() or 800
        margin = size * 2
        # Rough bounds in hex space
        q0, r0 = hex_round(*pixel_to_hex_float(-margin, -margin, size, self.origin))
        q1, r1 = hex_round(*pixel_to_hex_float(w + margin, h + margin, size, self.origin))
        for r in range(min(r0, r1) - 2, max(r0, r1) + 2):
            for q in range(min(q0, q1) - 2, max(q0, q1) + 2):
                if (q, r) in self.tiles:
                    continue
                px, py = hex_to_pixel(q, r, size, self.origin)
                if -margin < px < w + margin and -margin < py < h + margin:
                    corners = hex_corners(px, py, size)
                    flat = [c for pt in corners for c in pt]
                    self.canvas.create_polygon(flat, fill="", outline="#2a2a4a", width=1)

    @staticmethod
    def _lighten(hex_color, amount):
        """Lighten a #rrggbb color by adding amount (0-1) to each channel."""
        r = int(hex_color[1:3], 16)
        g = int(hex_color[3:5], 16)
        b = int(hex_color[5:7], 16)
        r = min(255, r + int(amount * 255))
        g = min(255, g + int(amount * 255))
        b = min(255, b + int(amount * 255))
        return f"#{r:02x}{g:02x}{b:02x}"

    # ------------------------------------------------------------------
    # File I/O
    # ------------------------------------------------------------------
    def _tile_to_dict(self, q, r, tile):
        return {
            "q": q,
            "r": r,
            "elevation": tile["elevation"],
            "terrain_type": tile["terrain_type"],
            "ramp_edges": list(tile["ramp_edges"]),
        }

    def _to_json(self):
        tiles_list = [self._tile_to_dict(q, r, t) for (q, r), t in sorted(self.tiles.items())]
        return json.dumps({"tiles": tiles_list}, indent=2)

    def _save(self):
        if self.filepath is None:
            self._save_as()
            return
        with open(self.filepath, "w") as f:
            f.write(self._to_json())
        self.status.config(text=f"Saved → {os.path.basename(self.filepath)}")

    def _save_as(self):
        path = filedialog.asksaveasfilename(
            defaultextension=".json",
            filetypes=[("JSON files", "*.json"), ("All files", "*.*")],
            initialdir=os.path.join(os.path.dirname(__file__), "..", "data", "maps"),
        )
        if path:
            self.filepath = path
            self._save()

    def _load(self):
        path = filedialog.askopenfilename(
            filetypes=[("JSON files", "*.json"), ("All files", "*.*")],
            initialdir=os.path.join(os.path.dirname(__file__), "..", "data", "maps"),
        )
        if not path:
            return
        try:
            with open(path) as f:
                data = json.load(f)
            self.tiles = {}
            for t in data.get("tiles", []):
                key = (int(t["q"]), int(t["r"]))
                self.tiles[key] = {
                    "elevation":    int(t.get("elevation", 0)),
                    "terrain_type": str(t.get("terrain_type", DEFAULT_TERRAIN)),
                    "ramp_edges":   [bool(x) for x in t.get("ramp_edges", [False] * 6)],
                }
            self.filepath = path
            self.root.title(f"Hex Map Editor — {os.path.basename(path)}")
            self._redraw()
            self.status.config(text=f"Loaded {len(self.tiles)} tiles from {os.path.basename(path)}")
        except Exception as e:
            messagebox.showerror("Load error", str(e))


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
def main():
    root = tk.Tk()
    root.geometry("1200x800")
    root.configure(bg="#1a1a2e")
    app = MapEditor(root)

    # If a path was passed on the command line, load it immediately
    if len(sys.argv) > 1 and os.path.isfile(sys.argv[1]):
        app.filepath = sys.argv[1]
        try:
            with open(sys.argv[1]) as f:
                data = json.load(f)
            for t in data.get("tiles", []):
                key = (int(t["q"]), int(t["r"]))
                app.tiles[key] = {
                    "elevation":    int(t.get("elevation", 0)),
                    "terrain_type": str(t.get("terrain_type", DEFAULT_TERRAIN)),
                    "ramp_edges":   [bool(x) for x in t.get("ramp_edges", [False] * 6)],
                }
            root.title(f"Hex Map Editor — {os.path.basename(sys.argv[1])}")
            app._redraw()
        except Exception as e:
            print(f"Failed to load {sys.argv[1]}: {e}")

    root.mainloop()


if __name__ == "__main__":
    main()
