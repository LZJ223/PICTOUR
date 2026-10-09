"""Read-only inspection of four separated atlas forms. Never rewrites image pixels."""

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


def inspect(path: Path) -> dict:
    image = Image.open(path).convert("RGBA")
    rgba = np.asarray(image)
    height, width = rgba.shape[:2]
    result = {"path": str(path), "size": [width, height], "regions": []}
    alpha = (rgba[:, :, 3] > 38).astype(np.uint8)
    count, labels, stats, centers = cv2.connectedComponentsWithStats(alpha)
    indices = sorted(range(1, count), key=lambda index: -stats[index, 4])[:4]
    indices.sort(key=lambda index: (int(centers[index, 1] // (height*.4)), centers[index, 0]))
    for index in indices:
        left, top, box_width, box_height, _ = map(int, stats[index])
        crop = (labels[top:top+box_height, left:left+box_width] == index).astype(np.uint8)
        contours, _ = cv2.findContours(crop, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        traced = []
        for contour in contours:
            if cv2.contourArea(contour) < 150:
                continue
            approximation = cv2.approxPolyDP(contour, 4, True).reshape(-1, 2)
            traced.append(np.round(approximation / [box_width, box_height], 4).tolist())
        result["regions"].append({
            "region": [left, top, box_width, box_height],
            "outer_alpha_contours": traced,
            "note": "Picking aid only; foliage and broken ink are not physical solids.",
        })
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    arguments = parser.parse_args()
    print(json.dumps(inspect(arguments.image), ensure_ascii=False, indent=2))
