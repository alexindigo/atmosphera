"""
HCT (Hue, Chroma, Tone) Color Space Implementation.

Based on Material Color Utilities (Google).
HCT combines CAM16 hue and chroma with CIELAB lightness (L*) for
Material Design 3's perceptual color space.
"""

from __future__ import annotations
import math

# =============================================================================
# Type Definitions
# =============================================================================

RGB = tuple[int, int, int]

# =============================================================================
# CAM16 / HCT Color Space Implementation
# =============================================================================

# sRGB to XYZ matrix (D65 illuminant)
SRGB_TO_XYZ = [
    [0.41233895, 0.35762064, 0.18051042],
    [0.2126, 0.7152, 0.0722],
    [0.01932141, 0.11916382, 0.95034478],
]

# XYZ to sRGB matrix
XYZ_TO_SRGB = [
    [3.2413774792388685, -1.5376652402851851, -0.49885366846268053],
    [-0.9691452513005321, 1.8758853451067872, 0.04156585616912061],
    [0.05562093689691305, -0.20395524564742123, 1.0571799111220335],
]


class ViewingConditions:
    """CAM16 viewing conditions for sRGB display."""
    # White point (D65)
    WHITE_POINT_D65 = [95.047, 100.0, 108.883]

    # Precomputed values for standard conditions
    n = 0.18418651851244416
    aw = 29.980997194447333
    nbb = 1.0169191804458755
    ncb = 1.0169191804458755
    c = 0.69
    nc = 1.0
    fl = 0.3884814537800353
    fl_root = 0.7894826179304937
    z = 1.909169568483652

    # RGB to CAM16 adaptation matrix
    RGB_D = [1.0211931250282205, 0.9862992588498498, 0.9338046048498166]


def _linearize(channel: int) -> float:
    """Convert sRGB channel (0-255) to linear RGB (0-1)."""
    normalized = channel / 255.0
    if normalized <= 0.040449936:
        return normalized / 12.92
    return math.pow((normalized + 0.055) / 1.055, 2.4)


def _delinearize(linear: float) -> int:
    """Convert linear RGB (0-1) to sRGB channel (0-255)."""
    if linear <= 0.0031308:
        normalized = linear * 12.92
    else:
        normalized = 1.055 * math.pow(linear, 1.0 / 2.4) - 0.055
    return max(0, min(255, round(normalized * 255)))


def _matrix_multiply(matrix: list[list[float]], vector: list[float]) -> list[float]:
    """Multiply 3x3 matrix by 3-element vector."""
    return [
        matrix[0][0] * vector[0] + matrix[0][1] * vector[1] + matrix[0][2] * vector[2],
        matrix[1][0] * vector[0] + matrix[1][1] * vector[1] + matrix[1][2] * vector[2],
        matrix[2][0] * vector[0] + matrix[2][1] * vector[1] + matrix[2][2] * vector[2],
    ]


def _signum(x: float) -> float:
    """Return sign of x: -1, 0, or 1."""
    if x < 0:
        return -1.0
    elif x > 0:
        return 1.0
    return 0.0


def _lerp(a: float, b: float, t: float) -> float:
    """Linear interpolation between a and b."""
    return a + (b - a) * t


def rgb_to_xyz(r: int, g: int, b: int) -> tuple[float, float, float]:
    """Convert sRGB to CIE XYZ."""
    linear_r = _linearize(r)
    linear_g = _linearize(g)
    linear_b = _linearize(b)
    xyz = _matrix_multiply(SRGB_TO_XYZ, [linear_r, linear_g, linear_b])
    return (xyz[0] * 100, xyz[1] * 100, xyz[2] * 100)


def xyz_to_rgb(x: float, y: float, z: float) -> tuple[int, int, int]:
    """Convert CIE XYZ to sRGB."""
    linear = _matrix_multiply(XYZ_TO_SRGB, [x / 100, y / 100, z / 100])
    return (_delinearize(linear[0]), _delinearize(linear[1]), _delinearize(linear[2]))


def y_to_lstar(y: float) -> float:
    """Convert XYZ Y component to L* (CIELAB lightness / HCT Tone)."""
    if y <= 0:
        return 0.0
    y_normalized = y / 100.0
    if y_normalized <= 0.008856:
        return 903.2962962962963 * y_normalized
    return 116.0 * math.pow(y_normalized, 1.0 / 3.0) - 16.0


def lstar_to_y(lstar: float) -> float:
    """Convert L* (Tone) to XYZ Y component."""
    if lstar <= 0:
        return 0.0
    if lstar > 100:
        lstar = 100.0
    if lstar <= 8.0:
        return lstar / 903.2962962962963 * 100.0
    fy = (lstar + 16.0) / 116.0
    return fy * fy * fy * 100.0


def argb_to_int(r: int, g: int, b: int) -> int:
    """Convert RGB to ARGB integer (alpha = 255)."""
    return (255 << 24) | (r << 16) | (g << 8) | b


def int_to_rgb(argb: int) -> tuple[int, int, int]:
    """Convert ARGB integer to RGB tuple."""
    return ((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF)


class Cam16:
    """CAM16 color appearance model representation."""

    def __init__(self, hue: float, chroma: float, j: float, q: float,
                 m: float, s: float, jstar: float, astar: float, bstar: float):
        self.hue = hue
        self.chroma = chroma
        self.j = j  # Lightness
        self.q = q  # Brightness
        self.m = m  # Colorfulness
        self.s = s  # Saturation
        self.jstar = jstar  # CAM16-UCS J*
        self.astar = astar  # CAM16-UCS a*
        self.bstar = bstar  # CAM16-UCS b*

    @classmethod
    def from_rgb(cls, r: int, g: int, b: int) -> 'Cam16':
        """Create CAM16 from sRGB values."""
        x, y, z = rgb_to_xyz(r, g, b)

        r_c = 0.401288 * x + 0.650173 * y - 0.051461 * z
        g_c = -0.250268 * x + 1.204414 * y + 0.045854 * z
        b_c = -0.002079 * x + 0.048952 * y + 0.953127 * z

        r_d = ViewingConditions.RGB_D[0] * r_c
        g_d = ViewingConditions.RGB_D[1] * g_c
        b_d = ViewingConditions.RGB_D[2] * b_c

        r_af = math.pow(ViewingConditions.fl * abs(r_d) / 100.0, 0.42)
        g_af = math.pow(ViewingConditions.fl * abs(g_d) / 100.0, 0.42)
        b_af = math.pow(ViewingConditions.fl * abs(b_d) / 100.0, 0.42)

        r_a = _signum(r_d) * 400.0 * r_af / (r_af + 27.13)
        g_a = _signum(g_d) * 400.0 * g_af / (g_af + 27.13)
        b_a = _signum(b_d) * 400.0 * b_af / (b_af + 27.13)

        a = (11.0 * r_a + -12.0 * g_a + b_a) / 11.0
        b = (r_a + g_a - 2.0 * b_a) / 9.0

        hue_radians = math.atan2(b, a)
        hue = math.degrees(hue_radians)
        if hue < 0:
            hue += 360.0

        u = (20.0 * r_a + 20.0 * g_a + 21.0 * b_a) / 20.0
        p2 = (40.0 * r_a + 20.0 * g_a + b_a) / 20.0
        ac = p2 * ViewingConditions.nbb

        j = 100.0 * math.pow(ac / ViewingConditions.aw, ViewingConditions.c * ViewingConditions.z)
        q = (4.0 / ViewingConditions.c) * math.sqrt(j / 100.0) * (ViewingConditions.aw + 4.0) * ViewingConditions.fl_root

        hue_prime = hue + 360.0 if hue < 20.14 else hue
        e_hue = 0.25 * (math.cos(math.radians(hue_prime) + 2.0) + 3.8)

        t = 50000.0 / 13.0 * ViewingConditions.nc * ViewingConditions.ncb * e_hue * math.sqrt(a * a + b * b) / (u + 0.305)
        alpha = math.pow(t, 0.9) * math.pow(1.64 - math.pow(0.29, ViewingConditions.n), 0.73)
        chroma = alpha * math.sqrt(j / 100.0)

        m = chroma * ViewingConditions.fl_root
        s = 50.0 * math.sqrt((ViewingConditions.c * alpha) / (ViewingConditions.aw + 4.0))

        jstar = (1.0 + 100.0 * 0.007) * j / (1.0 + 0.007 * j)
        mstar = 1.0 / 0.0228 * math.log(1.0 + 0.0228 * m) if m > 0 else 0
        astar = mstar * math.cos(hue_radians)
        bstar = mstar * math.sin(hue_radians)

        return cls(hue, chroma, j, q, m, s, jstar, astar, bstar)

    @classmethod
    def from_jch(cls, j: float, chroma: float, hue: float) -> 'Cam16':
        """Create CAM16 from J (lightness), chroma, and hue."""
        q = (4.0 / ViewingConditions.c) * math.sqrt(j / 100.0) * (ViewingConditions.aw + 4.0) * ViewingConditions.fl_root
        m = chroma * ViewingConditions.fl_root
        alpha = chroma / math.sqrt(j / 100.0) if j > 0 else 0
        s = 50.0 * math.sqrt((ViewingConditions.c * alpha) / (ViewingConditions.aw + 4.0))

        hue_radians = math.radians(hue)
        jstar = (1.0 + 100.0 * 0.007) * j / (1.0 + 0.007 * j)
        mstar = 1.0 / 0.0228 * math.log(1.0 + 0.0228 * m) if m > 0 else 0
        astar = mstar * math.cos(hue_radians)
        bstar = mstar * math.sin(hue_radians)

        return cls(hue, chroma, j, q, m, s, jstar, astar, bstar)

    def to_rgb(self) -> tuple[int, int, int]:
        """Convert CAM16 back to sRGB."""
        if self.chroma == 0 or self.j == 0:
            y = lstar_to_y(self.j)
            return xyz_to_rgb(y, y, y)

        hue_radians = math.radians(self.hue)

        alpha = self.chroma / math.sqrt(self.j / 100.0) if self.j > 0 else 0
        t = math.pow(alpha / math.pow(1.64 - math.pow(0.29, ViewingConditions.n), 0.73), 1.0 / 0.9)

        hue_prime = self.hue + 360.0 if self.hue < 20.14 else self.hue
        e_hue = 0.25 * (math.cos(math.radians(hue_prime) + 2.0) + 3.8)

        ac = ViewingConditions.aw * math.pow(self.j / 100.0, 1.0 / (ViewingConditions.c * ViewingConditions.z))
        p1 = 50000.0 / 13.0 * ViewingConditions.nc * ViewingConditions.ncb * e_hue
        p2 = ac / ViewingConditions.nbb

        gamma = 23.0 * (p2 + 0.305) * t / (23.0 * p1 + 11.0 * t * math.cos(hue_radians) + 108.0 * t * math.sin(hue_radians))

        a = gamma * math.cos(hue_radians)
        b = gamma * math.sin(hue_radians)

        r_a = (460.0 * p2 + 451.0 * a + 288.0 * b) / 1403.0
        g_a = (460.0 * p2 - 891.0 * a - 261.0 * b) / 1403.0
        b_a = (460.0 * p2 - 220.0 * a - 6300.0 * b) / 1403.0

        def reverse_adapt(adapted: float) -> float:
            abs_adapted = abs(adapted)
            base = max(0, 27.13 * abs_adapted / (400.0 - abs_adapted))
            return _signum(adapted) * 100.0 / ViewingConditions.fl * math.pow(base, 1.0 / 0.42)

        r_c = reverse_adapt(r_a) / ViewingConditions.RGB_D[0]
        g_c = reverse_adapt(g_a) / ViewingConditions.RGB_D[1]
        b_c = reverse_adapt(b_a) / ViewingConditions.RGB_D[2]

        x = 1.8620678 * r_c - 1.0112547 * g_c + 0.1491867 * b_c
        y = 0.3875265 * r_c + 0.6214474 * g_c - 0.0089739 * b_c
        z = -0.0158415 * r_c - 0.0344156 * g_c + 1.0502571 * b_c

        return xyz_to_rgb(x, y, z)


class Hct:
    """
    HCT (Hue, Chroma, Tone) color representation.

    Material Design 3's perceptual color space combining:
    - Hue: CAM16 hue (0-360)
    - Chroma: CAM16 chroma (colorfulness, typically 0-120+)
    - Tone: CIELAB L* lightness (0-100)
    """

    def __init__(self, hue: float, chroma: float, tone: float):
        self._hue = hue % 360.0
        self._chroma = max(0.0, chroma)
        self._tone = max(0.0, min(100.0, tone))
        self._argb: int | None = None

    @property
    def hue(self) -> float:
        return self._hue

    @property
    def chroma(self) -> float:
        return self._chroma

    @property
    def tone(self) -> float:
        return self._tone

    @classmethod
    def from_rgb(cls, r: int, g: int, b: int) -> 'Hct':
        """Create HCT from sRGB values."""
        cam = Cam16.from_rgb(r, g, b)
        _, y, _ = rgb_to_xyz(r, g, b)
        tone = y_to_lstar(y)
        return cls(cam.hue, cam.chroma, tone)

    @classmethod
    def from_argb(cls, argb: int) -> 'Hct':
        """Create HCT from ARGB integer."""
        r, g, b = int_to_rgb(argb)
        return cls.from_rgb(r, g, b)

    def to_rgb(self) -> tuple[int, int, int]:
        """Convert HCT to sRGB, solving for the color."""
        return self._solve_to_rgb(self._hue, self._chroma, self._tone)

    def to_argb(self) -> int:
        """Convert HCT to ARGB integer."""
        if self._argb is None:
            r, g, b = self.to_rgb()
            self._argb = argb_to_int(r, g, b)
        return self._argb

    def to_hex(self) -> str:
        """Convert HCT to hex string."""
        r, g, b = self.to_rgb()
        return f"#{r:02x}{g:02x}{b:02x}"

    @staticmethod
    def _solve_to_rgb(hue: float, chroma: float, tone: float) -> tuple[int, int, int]:
        """Solve for RGB given HCT values."""
        if tone <= 0.0:
            return (0, 0, 0)
        if tone >= 100.0:
            return (255, 255, 255)
        if chroma < 0.5:
            y = lstar_to_y(tone)
            return xyz_to_rgb(y, y, y)

        low_chroma = 0.0
        high_chroma = chroma
        best_rgb = None
        best_chroma = 0.0

        for iteration in range(20):
            mid_chroma = (low_chroma + high_chroma) / 2.0
            rgb = Hct._find_rgb_for_hct(hue, mid_chroma, tone)

            if rgb is not None:
                r, g, b = rgb
                if 0 <= r <= 255 and 0 <= g <= 255 and 0 <= b <= 255:
                    best_rgb = rgb
                    best_chroma = mid_chroma
                    low_chroma = mid_chroma
                else:
                    high_chroma = mid_chroma
            else:
                high_chroma = mid_chroma

        if best_rgb is not None:
            return best_rgb

        y = lstar_to_y(tone)
        return xyz_to_rgb(y, y, y)

    @staticmethod
    def _find_rgb_for_hct(hue: float, chroma: float, tone: float) -> tuple[int, int, int] | None:
        """Find an RGB color for the given HCT values."""
        j = tone

        for _ in range(5):
            cam = Cam16.from_jch(j, chroma, hue)
            rgb = cam.to_rgb()
            r, g, b = rgb

            r_clamped = max(0, min(255, r))
            g_clamped = max(0, min(255, g))
            b_clamped = max(0, min(255, b))

            if r != r_clamped or g != g_clamped or b != b_clamped:
                return None

            _, y, _ = rgb_to_xyz(r, g, b)
            actual_tone = y_to_lstar(y)

            tone_diff = tone - actual_tone
            if abs(tone_diff) < 0.5:
                return (r, g, b)

            j += tone_diff * 0.5

            if j <= 0 or j > 100:
                return None

        cam = Cam16.from_jch(j, chroma, hue)
        rgb = cam.to_rgb()
        r, g, b = rgb

        if 0 <= r <= 255 and 0 <= g <= 255 and 0 <= b <= 255:
            return (r, g, b)

        return None

    def set_hue(self, hue: float) -> 'Hct':
        """Return new HCT with different hue."""
        return Hct(hue, self._chroma, self._tone)

    def set_chroma(self, chroma: float) -> 'Hct':
        """Return new HCT with different chroma."""
        return Hct(self._hue, chroma, self._tone)

    def set_tone(self, tone: float) -> 'Hct':
        """Return new HCT with different tone."""
        return Hct(self._hue, self._chroma, tone)


class TonalPalette:
    """
    A palette of tones for a single hue and chroma.

    Material Design 3 uses specific tone values for different UI elements.
    """

    def __init__(self, hue: float, chroma: float):
        self.hue = hue
        self.chroma = chroma
        self._cache: dict[int, int] = {}

    @classmethod
    def from_hct(cls, hct: Hct) -> 'TonalPalette':
        """Create TonalPalette from HCT color."""
        return cls(hct.hue, hct.chroma)

    @classmethod
    def from_rgb(cls, r: int, g: int, b: int) -> 'TonalPalette':
        """Create TonalPalette from RGB color."""
        hct = Hct.from_rgb(r, g, b)
        return cls(hct.hue, hct.chroma)

    def tone(self, t: int) -> int:
        """Get ARGB color at the specified tone (0-100)."""
        if t not in self._cache:
            hct = Hct(self.hue, self.chroma, float(t))
            self._cache[t] = hct.to_argb()
        return self._cache[t]

    def get_rgb(self, t: int) -> tuple[int, int, int]:
        """Get RGB color at the specified tone."""
        return int_to_rgb(self.tone(t))

    def get_hex(self, t: int) -> str:
        """Get hex color at the specified tone."""
        r, g, b = self.get_rgb(t)
        return f"#{r:02x}{g:02x}{b:02x}"
