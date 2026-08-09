"""
DROZY Step 2: CNN Backbone Fine-tuning for Infrared Domain Adaptation
Fine-tunes the EfficientNet-B0 model on pseudo-RGB (3-channel duplicated grayscale) 
cropped face frames from DROZY development subjects.
"""

import torch
import torch.nn as nn
from torchvision import models
from PIL import Image
from torch.utils.data import Dataset, DataLoader
import pandas as pd
from pathlib import Path
import random
import numpy as np
from sklearn.metrics import accuracy_score, f1_score, classification_report
from tqdm import tqdm
import copy

# ── Seed ───────────────────────────────────────────────────────────────────
random.seed(42)
np.random.seed(42)
torch.manual_seed(42)
if torch.cuda.is_available():
    torch.cuda.manual_seed_all(42)

# ── Paths ──────────────────────────────────────────────────────────────────
PROJECT_ROOT = Path(__file__).parent.parent
DROZY_ROOT   = PROJECT_ROOT / "processed" / "DROZY" / "sequences"
CHECKPOINT_DIR = PROJECT_ROOT / "models" / "checkpoints"

# ── Split & Classes ───────────────────────────────────────────────────────
TEST_SUBJECTS = {"11", "14"}
TRAIN_SUBJECTS = {"1", "2", "3", "5", "6"}
VAL_SUBJECTS = {"4", "8"}

CLASS_MAP = {
    "alert": 0,
    "low_vigilant": 1,
    "drowsy": 2
}

def load_drozy_dataframe():
    """Load paths to cropped face images and match them with labels and subjects."""
    rows = []
    for subject_dir in sorted(DROZY_ROOT.iterdir()):
        if not subject_dir.is_dir():
            continue
        subject = subject_dir.name
        
        for cls_name, label_id in CLASS_MAP.items():
            cls_dir = subject_dir / cls_name
            if not cls_dir.exists():
                continue
            
            for img_path in cls_dir.glob("*.jpg"):
                rows.append({
                    "path": str(img_path),
                    "subject": subject,
                    "label": label_id
                })
    return pd.DataFrame(rows)

def sample_subject(df_sub, max_samples=200):
    """Balanced sampling: sample up to max_samples frames per class per subject."""
    sampled = []
    for s in df_sub["subject"].unique():
        sub = df_sub[df_sub["subject"] == s]
        for c in [0, 1, 2]:
            cls = sub[sub["label"] == c]
            n = min(max_samples, len(cls))
            if n > 0:
                sampled.append(cls.sample(n=n, random_state=42))
    return pd.concat(sampled) if len(sampled) > 0 else pd.DataFrame()

class DROZYDataset(Dataset):
    def __init__(self, df, transform):
        self.df = df.reset_index(drop=True)
        self.transform = transform

    def __len__(self):
        return len(self.df)

    def __getitem__(self, idx):
        row = self.df.iloc[idx]
        img = Image.open(row["path"]).convert("RGB")
        img = self.transform(img)
        label = int(row["label"])
        return img, label

def train_one_epoch(model, loader, criterion, optimizer, device):
    model.train()
    running_loss = 0
    preds = []
    labels = []

    for x, y in tqdm(loader, desc="Training", leave=False):
        x = x.to(device)
        y = y.to(device)

        optimizer.zero_grad()
        out = model(x)
        loss = criterion(out, y)
        loss.backward()
        optimizer.step()

        running_loss += loss.item()
        pred = out.argmax(1)
        preds.extend(pred.cpu().numpy())
        labels.extend(y.cpu().numpy())

    epoch_loss = running_loss / len(loader)
    epoch_acc = accuracy_score(labels, preds)
    epoch_f1 = f1_score(labels, preds, average="macro")
    return epoch_loss, epoch_acc, epoch_f1

def validate(model, loader, criterion, device):
    model.eval()
    running_loss = 0
    preds = []
    labels = []

    with torch.no_grad():
        for x, y in tqdm(loader, desc="Validating", leave=False):
            x = x.to(device)
            y = y.to(device)

            out = model(x)
            loss = criterion(out, y)
            running_loss += loss.item()

            pred = out.argmax(1)
            preds.extend(pred.cpu().numpy())
            labels.extend(y.cpu().numpy())

    epoch_loss = running_loss / len(loader)
    epoch_acc = accuracy_score(labels, preds)
    epoch_f1 = f1_score(labels, preds, average="macro")
    
    report = classification_report(
        labels, preds,
        target_names=["Alert", "Low Vigilant", "Drowsy"],
        digits=4, zero_division=0
    )
    return epoch_loss, epoch_acc, epoch_f1, report

def main():
    df = load_drozy_dataframe()
    print(f"Total frames found: {len(df)}")
    
    # Filter development dataset (excluding held-out test subjects)
    train_df = df[df["subject"].isin(TRAIN_SUBJECTS)]
    val_df = df[df["subject"].isin(VAL_SUBJECTS)]
    
    print(f"Initial split - Train subjects: {TRAIN_SUBJECTS}, Val subjects: {VAL_SUBJECTS}")
    
    # Apply balanced sampling (up to 200 samples per class per subject)
    train_df = sample_subject(train_df, max_samples=200)
    val_df = sample_subject(val_df, max_samples=200)
    
    print(f"Sampled train size: {len(train_df)}")
    print(f"Sampled validation size: {len(val_df)}")
    print("\nTrain class distribution:\n", train_df["label"].value_counts().sort_index())
    print("\nVal class distribution:\n", val_df["label"].value_counts().sort_index())
    
    # Transformations
    transform = models.EfficientNet_B0_Weights.DEFAULT.transforms()
    
    train_dataset = DROZYDataset(train_df, transform)
    val_dataset = DROZYDataset(val_df, transform)
    
    train_loader = DataLoader(train_dataset, batch_size=32, shuffle=True, num_workers=2, pin_memory=True)
    val_loader = DataLoader(val_dataset, batch_size=32, shuffle=False, num_workers=2, pin_memory=True)
    
    # Model configuration
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"\nUsing device: {device}")
    
    model = models.efficientnet_b0(weights=None)
    model.classifier = nn.Sequential(
        nn.Dropout(0.3),
        nn.Linear(1280, 512),
        nn.ReLU(),
        nn.Dropout(0.3),
        nn.Linear(512, 3)
    )
    
    # Load UTA pre-trained 3-class CNN checkpoint
    checkpoint_path = CHECKPOINT_DIR / "best_cnn_3class.pth"
    if checkpoint_path.exists():
        model.load_state_dict(torch.load(checkpoint_path, map_location=device))
        print("Loaded initial pre-trained 3-class CNN weights.")
    else:
        print("[WARNING] best_cnn_3class.pth not found! Starting with uninitialized classifier.")
    
    # Freeze layers except the last 2 features blocks and classifier
    for param in model.parameters():
        param.requires_grad = False
    for param in model.features[-2:].parameters():
        param.requires_grad = True
    for param in model.classifier.parameters():
        param.requires_grad = True
        
    model = model.to(device)
    
    # Optimizer & Loss
    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.Adam(
        filter(lambda p: p.requires_grad, model.parameters()),
        lr=1e-5
    )
    
    # Training Loop
    NUM_EPOCHS = 15
    PATIENCE = 5
    best_f1 = 0
    counter = 0
    best_model_weights = None
    
    print("\nStarting CNN fine-tuning...")
    for epoch in range(NUM_EPOCHS):
        train_loss, train_acc, train_f1 = train_one_epoch(model, train_loader, criterion, optimizer, device)
        val_loss, val_acc, val_f1, report = validate(model, val_loader, criterion, device)
        
        print(f"\nEpoch {epoch+1}/{NUM_EPOCHS}")
        print(f"  Train Loss: {train_loss:.4f} | Train Acc: {train_acc:.4f} | Train F1: {train_f1:.4f}")
        print(f"  Val Loss: {val_loss:.4f}   | Val Acc: {val_acc:.4f}   | Val F1: {val_f1:.4f}")
        
        if val_f1 > best_f1:
            best_f1 = val_f1
            counter = 0
            best_model_weights = copy.deepcopy(model.state_dict())
            torch.save(best_model_weights, CHECKPOINT_DIR / "best_cnn_3class_drozy.pth")
            print("  [NEW BEST] Model checkpoint saved to best_cnn_3class_drozy.pth")
        else:
            counter += 1
            print(f"  No improvement ({counter}/{PATIENCE})")
            if counter >= PATIENCE:
                print("  Early stopping triggered.")
                break
                
    print("\nFine-tuning completed!")

if __name__ == "__main__":
    main()
