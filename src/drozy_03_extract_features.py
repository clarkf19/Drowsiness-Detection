"""
DROZY Step 3: Feature Extraction & Subject-Wise Normalization
Extracts 512-dim spatial features using the fine-tuned EfficientNet-B0 backbone,
and performs subject-wise normalization using the Alert video baseline with a 1e-2 std floor.
"""

import numpy as np
from PIL import Image
import torch
import torch.nn as nn
from torchvision import models
from pathlib import Path
from tqdm import tqdm

# ── Paths ──────────────────────────────────────────────────────────────────
PROJECT_ROOT = Path(__file__).parent.parent
DROZY_ROOT   = PROJECT_ROOT / "processed" / "DROZY" / "sequences"
EMBED_ROOT   = PROJECT_ROOT / "processed" / "DROZY" / "embeddings"
NORM_ROOT    = PROJECT_ROOT / "processed" / "DROZY" / "normalized_embeddings"
MODEL_PATH   = PROJECT_ROOT / "models" / "checkpoints" / "best_cnn_3class_drozy.pth"

# Create directories
EMBED_ROOT.mkdir(parents=True, exist_ok=True)
NORM_ROOT.mkdir(parents=True, exist_ok=True)

# ── Model configuration ─────────────────────────────────────────────────────
device = "cuda" if torch.cuda.is_available() else "cpu"
print(f"Using device: {device}")

model = models.efficientnet_b0(weights=None)
model.classifier = nn.Sequential(
    nn.Dropout(0.3),
    nn.Linear(1280, 512),
    nn.ReLU(),
    nn.Dropout(0.3),
    nn.Linear(512, 3)
)

if MODEL_PATH.exists():
    model.load_state_dict(torch.load(MODEL_PATH, map_location=device))
    print(f"Loaded fine-tuned DROZY CNN weights from {MODEL_PATH.name}")
else:
    raise FileNotFoundError(f"Could not find DROZY CNN checkpoint at {MODEL_PATH}")

model = model.to(device)
model.eval()

# Construct identical feature extractor
feature_extractor = nn.Sequential(
    model.features,
    model.avgpool,
    nn.Flatten(),
    model.classifier[0],  # Dropout
    model.classifier[1],  # Linear
    model.classifier[2]   # ReLU
).to(device)

feature_extractor.eval()

# Transformations
transform = models.EfficientNet_B0_Weights.DEFAULT.transforms()

# ── Step 1: Feature Extraction ──────────────────────────────────────────────
subjects = sorted([p.name for p in DROZY_ROOT.iterdir() if p.is_dir()])
print(f"Extracting features for {len(subjects)} subjects: {subjects}")

for subject in subjects:
    print(f"\nProcessing subject {subject}...")
    sub_dir = DROZY_ROOT / subject
    save_dir = EMBED_ROOT / subject
    save_dir.mkdir(parents=True, exist_ok=True)
    
    for cls in ["alert", "low_vigilant", "drowsy"]:
        frame_dir = sub_dir / cls
        if not frame_dir.exists():
            print(f"  [WARNING] {cls} directory not found for subject {subject}")
            continue
            
        frame_paths = sorted(frame_dir.glob("*.jpg"))
        if len(frame_paths) == 0:
            print(f"  [WARNING] No frames found in {frame_dir}")
            continue
            
        embeddings = []
        for img_path in tqdm(frame_paths, desc=f"  {cls}", leave=False):
            img = Image.open(img_path).convert("RGB")
            x = transform(img).unsqueeze(0).to(device)
            
            with torch.no_grad():
                emb = feature_extractor(x)
                
            embeddings.append(emb.squeeze().cpu().numpy())
            
        embeddings = np.array(embeddings, dtype=np.float32)
        save_path = save_dir / f"{cls}.npy"
        np.save(save_path, embeddings)
        print(f"  Saved {cls}.npy: {embeddings.shape}")

# ── Step 2: Subject-Wise Normalization ──────────────────────────────────────
print("\nPerforming subject-wise normalization with 1e-2 standard deviation floor...")

for subject in subjects:
    sub_embed_dir = EMBED_ROOT / subject
    sub_norm_dir = NORM_ROOT / subject
    sub_norm_dir.mkdir(parents=True, exist_ok=True)
    
    alert_path = sub_embed_dir / "alert.npy"
    low_path = sub_embed_dir / "low_vigilant.npy"
    drowsy_path = sub_embed_dir / "drowsy.npy"
    
    if not (alert_path.exists() and low_path.exists() and drowsy_path.exists()):
        print(f"  [SKIP] Subject {subject}: missing some embedding files")
        continue
        
    alert = np.load(alert_path)
    low = np.load(low_path)
    drowsy = np.load(drowsy_path)
    
    if len(alert) == 0 or len(low) == 0 or len(drowsy) == 0:
        print(f"  [SKIP] Subject {subject}: empty embeddings")
        continue
        
    # Baseline stats computed ONLY from the alert state
    mean = alert.mean(axis=0)
    std = alert.std(axis=0)
    
    # 1e-2 floor clamp to prevent feature explosion
    std = np.clip(std, a_min=1e-2, a_max=None)
    
    # Normalize
    alert_norm = (alert - mean) / std
    low_norm = (low - mean) / std
    drowsy_norm = (drowsy - mean) / std
    
    np.save(sub_norm_dir / "alert.npy", alert_norm.astype(np.float32))
    np.save(sub_norm_dir / "low_vigilant.npy", low_norm.astype(np.float32))
    np.save(sub_norm_dir / "drowsy.npy", drowsy_norm.astype(np.float32))
    np.save(sub_norm_dir / "mean.npy", mean.astype(np.float32))
    np.save(sub_norm_dir / "std.npy", std.astype(np.float32))
    
    print(f"  Normalized subject {subject}: shape alert={alert_norm.shape}, low={low_norm.shape}, drowsy={drowsy_norm.shape}")

print("\nAll steps completed! Sample stats for Subject 1 (alert norm):")
sample_norm = np.load(NORM_ROOT / "1" / "alert.npy")
print(f"  Mean (should be near 0): {sample_norm.mean():.6f}")
print(f"  Std  (should be near 1): {sample_norm.std():.6f}")
