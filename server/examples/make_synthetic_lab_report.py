"""Generate an explicitly fictional OCR fixture. Never use as agricultural evidence."""

import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

TEXT = """SYNTHETIC SOFTWARE TEST - NOT A REAL LAB REPORT
Laboratory: Example Test Laboratory
Sample ID: TEST-1
Sample date: 2026-01-15
Test method: pH in water
Sampling depth: 0-15 cm
pH: 6.4
Phosphorus: 12 mg/kg
Potassium: 80 mg/kg
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--font",
        default="DejaVuSans.ttf",
        help="Path to a locally installed TrueType font",
    )
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Choose a new output file")
    image = Image.new("RGB", (1600, 750), "white")
    ImageDraw.Draw(image).multiline_text(
        (35, 30), TEXT, font=ImageFont.truetype(args.font, 30), fill="black", spacing=12
    )
    image.save(args.output, format="PNG")
    print("Created labeled synthetic software-test fixture")


if __name__ == "__main__":
    main()
