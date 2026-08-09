"""
DROZY Step 1: Frame Extraction and Face Cropping
Extracts frames from DROZY NIR videos, detects faces using MediaPipe,
and saves cropped face images organized by subject and state.

Label mapping:
  X-1.mp4 -> Alert (0)
  X-2.mp4 -> Low Vigilant (1)
  X-3.mp4 -> Drowsy (2)

Only subjects with ALL 3 videos are processed (fully usable set):
  1, 2, 3, 4, 5, 6, 8, 11, 14
"""

import cv2
import mediapipe as mp
import numpy as np
from pathlib import Path
from tqdm import tqdm
import re

# ── Paths ──────────────────────────────────────────────────────────────────
PROJECT_ROOT = Path(__file__).parent.parent
DROZY_ROOT   = PROJECT_ROOT / "datasets" / "DROZY"
SAVE_ROOT    = PROJECT_ROOT / "processed" / "DROZY" / "sequences"

# Only subjects with all 3 videos (Alert, Low Vigilant, Drowsy)
VALID_SUBJECTS = {1, 2, 3, 4, 5, 6, 8, 11, 14}
STATE_MAP = {"1": "alert", "2": "low_vigilant", "3": "drowsy"}

# ── MediaPipe face detection ──────────────────────────────────────────────
mp_face = mp.solutions.face_detection
face_detector = mp_face.FaceDetection(
    model_selection=1,
    min_detection_confidence=0.4
)

TARGET_SIZE = (224, 224)


def extract_face(frame_bgr):
    """Detect face and return cropped+resized BGR patch, or None if not found."""
    rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    result = face_detector.process(rgb)

    if not result.detections:
        return None

    h, w = frame_bgr.shape[:2]
    det = result.detections[0]
    bb  = det.location_data.relative_bounding_box

    x1 = max(0, int(bb.xmin * w))
    y1 = max(0, int(bb.ymin * h))
    x2 = min(w, int((bb.xmin + bb.width)  * w))
    y2 = min(h, int((bb.ymin + bb.height) * h))

    if x2 - x1 < 10 or y2 - y1 < 10:
        return None

    crop = frame_bgr[y1:y2, x1:x2]
    return cv2.resize(crop, TARGET_SIZE)


def process_video(video_path: Path, save_dir: Path):
    """Extract face frames from one video and save as sequential JPEGs (1 FPS)."""
    save_dir.mkdir(parents=True, exist_ok=True)

    cap = cv2.VideoCapture(str(video_path))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    
    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0:
        fps = 30
    fps = max(1, int(round(fps)))

    saved = 0
    skipped = 0
    frame_idx = 0
    saved_idx = 0

    with tqdm(total=total, desc=video_path.name, leave=False) as pbar:
        while True:
            ret, frame = cap.read()
            if not ret:
                break

            if frame_idx % fps == 0:
                face = extract_face(frame)
                if face is not None:
                    fname = save_dir / f"frame_{saved_idx:06d}.jpg"
                    cv2.imwrite(str(fname), face, [cv2.IMWRITE_JPEG_QUALITY, 95])
                    saved += 1
                    saved_idx += 1
                else:
                    skipped += 1

            frame_idx += 1
            pbar.update(1)

    cap.release()
    return saved, skipped



def main():
    mp4_files = sorted(DROZY_ROOT.glob("*.mp4"))
    print(f"Found {len(mp4_files)} MP4 files in DROZY dataset")
    print(f"Processing subjects: {sorted(VALID_SUBJECTS)}")
    print()

    total_saved = 0
    total_skipped = 0

    for mp4 in mp4_files:
        match = re.match(r"^(\d+)-(\d+)\.mp4$", mp4.name)
        if not match:
            print(f"  [SKIP] Unrecognized filename: {mp4.name}")
            continue

        subject_id = int(match.group(1))
        state_id   = match.group(2)

        if subject_id not in VALID_SUBJECTS:
            print(f"  [SKIP] Subject {subject_id}: not in valid set")
            continue

        if state_id not in STATE_MAP:
            print(f"  [SKIP] {mp4.name}: unrecognised state")
            continue

        state_name = STATE_MAP[state_id]
        save_dir   = SAVE_ROOT / str(subject_id) / state_name

        print(f"  Processing {mp4.name} -> subject={subject_id}, state={state_name}")
        saved, skipped = process_video(mp4, save_dir)
        print(f"    Saved: {saved}, Skipped (no face): {skipped}")
        total_saved   += saved
        total_skipped += skipped

    print()
    print(f"Done! Total saved: {total_saved}, Total skipped: {total_skipped}")


if __name__ == "__main__":
    main()
