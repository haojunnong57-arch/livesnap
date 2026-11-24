#!/usr/bin/env python3
"""Generates the 1024pt app icon: Apple's native Live Photo glyph on black."""

import math
import os
import struct
import zlib

SIZE = 1024
OUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "LiveSnap", "Resources", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png",
)


def smoothstep(edge0, edge1, value):
    if edge1 <= edge0:
        return 0.0 if value < edge0 else 1.0
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def ring(radius_distance, target, width):
    inner = target - width / 2.0
    outer = target + width / 2.0
    return smoothstep(inner - 1.1, inner + 1.1, radius_distance) * (
        1.0 - smoothstep(outer - 1.1, outer + 1.1, radius_distance)
    )


def render():
    pixels = bytearray(SIZE * SIZE * 3)
    center = SIZE / 2.0

    for y in range(SIZE):
        fy = y / SIZE
        for x in range(SIZE):
            fx = x / SIZE
            dx = x - center
            dy = y - center
            distance = math.hypot(dx, dy)

            # 中心极淡的白光，让图形有原生徽标的浮起感
            halo = math.exp(-((distance / 360.0) ** 2)) * 0.05

            # Apple 原生实况图标：外环 + 中环 + 实心圆点
            alpha = max(
                ring(distance, 300.0, 30.0),
                ring(distance, 206.0, 26.0),
                1.0 - smoothstep(78.0, 82.0, distance),
            )
            alpha = min(1.0, max(alpha, halo))

            # 纯黑背景 + 白灰徽标
            glyph = 246.0 - 26.0 * smoothstep(0.15, 0.95, fy)
            r = glyph * alpha
            g = glyph * alpha
            b = (glyph + 4.0) * alpha

            index = (y * SIZE + x) * 3
            pixels[index] = max(0, min(255, int(r)))
            pixels[index + 1] = max(0, min(255, int(g)))
            pixels[index + 2] = max(0, min(255, int(b)))

    return pixels


def write_png(path, width, height, pixels):
    raw = bytearray()
    stride = width * 3
    for y in range(height):
        raw.append(0)
        raw.extend(pixels[y * stride:(y + 1) * stride])

    def chunk(tag, payload):
        checksum = zlib.crc32(tag + payload) & 0xFFFFFFFF
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", checksum))

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(bytes([137, 80, 78, 71, 13, 10, 26, 10]))
        handle.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        handle.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        handle.write(chunk(b"IEND", b""))


def main():
    pixels = render()
    write_png(OUT, SIZE, SIZE, pixels)
    print("icon written:", OUT)


if __name__ == "__main__":
    main()
