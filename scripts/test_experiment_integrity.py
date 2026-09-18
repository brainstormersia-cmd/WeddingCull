import os
import sys
import re

SCRIPTS_DIR = "X:/AutoMAT/scripts"

FORBIDDEN_PATTERNS = [
    (r"\bimport\s+cv2\b", "OpenCV import (cv2)"),
    (r"\bfrom\s+cv2\b", "OpenCV import (cv2)"),
    (r"\bimport\s+PIL\b", "PIL import"),
    (r"\bfrom\s+PIL\b", "PIL import"),
    (r"\bimport\s+imageio\b", "imageio import"),
    (r"\bimport\s+skimage\b", "skimage import"),
]

# Scripts subject to ranking/modeling integrity rules (excluding dataset extraction/auditing scripts)
RANKING_SCRIPT_PATTERNS = [
    r".*ranker.*\.py$",
    r".*ablation.*\.py$",
    r".*evaluator.*\.py$",
]

def main():
    print("=== Running Experiment Integrity Static Analysis ===")
    violations = []
    checked_files = 0

    for fname in os.listdir(SCRIPTS_DIR):
        fpath = os.path.join(SCRIPTS_DIR, fname)
        if not os.path.isfile(fpath) or not fname.endswith(".py"):
            continue

        # Check if file is subject to ranking/modeling integrity rules
        is_ranking_script = any(re.match(p, fname) for p in RANKING_SCRIPT_PATTERNS)
        if not is_ranking_script:
            continue

        checked_files += 1
        with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()

        for pattern, desc in FORBIDDEN_PATTERNS:
            match = re.search(pattern, content)
            if match:
                violations.append((fname, desc, match.group(0)))

        # Also assert it does not have an image root argument
        if "--image-root" in content or "--dataset-images" in content:
            violations.append((fname, "Image Root CLI Arg", "Found image-root argument in ranking script"))

    print(f"Checked {checked_files} ranking/modeling scripts.")
    if violations:
        print(f"FAILED: Found {len(violations)} integrity violations:")
        for fname, desc, detail in violations:
            print(f"  - [{fname}] {desc}: {detail}")
        sys.exit(1)
    else:
        print("PASSED: Zero forbidden image I/O imports found in ranking scripts.")

if __name__ == "__main__":
    main()
