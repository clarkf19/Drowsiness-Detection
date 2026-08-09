"""
Points 1-7: Export PyTorch CNN + LSTM models to ONNX then TFLite.

CNN architecture: EfficientNet-B0 with custom classifier
  features -> avgpool -> Flatten -> Dropout(0.3) -> Linear(1280,512) -> ReLU -> [stop here = 512-dim embedding]

LSTM architecture: DrowsinessLSTM
  LSTM(512->64, 2 layers) -> BN1d(64) -> Dropout(0.5) -> Linear(64,3)

Run from the project root:
  venv\Scripts\python.exe src\export_models.py
"""

import time
import numpy as np
import torch
import torch.nn as nn
from torchvision import models
from pathlib import Path
import sys

sys.path.append(str(Path(__file__).parent.parent))
from src.lstm_model import DrowsinessLSTM

# ── Paths ─────────────────────────────────────────────────────────────────────
PROJECT_ROOT   = Path(__file__).parent.parent
CKPT_DIR       = PROJECT_ROOT / "models" / "checkpoints"
EXPORT_DIR     = PROJECT_ROOT / "models" / "tflite"
EXPORT_DIR.mkdir(parents=True, exist_ok=True)

device = "cpu"   # Export on CPU for maximum compatibility


# =============================================================================
# POINT 1 – Build + load both models
# =============================================================================
print("\n" + "="*60)
print("POINT 1 – Loading CNN and LSTM checkpoints")
print("="*60)

# ── CNN: full EfficientNet-B0 with custom classifier ─────────────────────────
cnn_full = models.efficientnet_b0(weights=None)
cnn_full.classifier = nn.Sequential(
    nn.Dropout(0.3),
    nn.Linear(1280, 512),
    nn.ReLU(),
    nn.Dropout(0.3),
    nn.Linear(512, 3)
)

cnn_ckpt = CKPT_DIR / "best_cnn_3class.pth"
assert cnn_ckpt.exists(), f"CNN checkpoint not found: {cnn_ckpt}"
cnn_full.load_state_dict(torch.load(cnn_ckpt, map_location=device))
cnn_full.eval()
print(f"  CNN loaded from: {cnn_ckpt.name}")

# ── CNN feature extractor (512-dim output, no final classifier head) ──────────
# Mirrors exactly what drozy_03_extract_features.py does
feature_extractor = nn.Sequential(
    cnn_full.features,
    cnn_full.avgpool,
    nn.Flatten(),
    cnn_full.classifier[0],   # Dropout(0.3)
    cnn_full.classifier[1],   # Linear(1280, 512)
    cnn_full.classifier[2],   # ReLU
).to(device)
feature_extractor.eval()
print(f"  Feature extractor built — output: 512-dim")

# ── LSTM ──────────────────────────────────────────────────────────────────────
lstm_model = DrowsinessLSTM().to(device)
lstm_ckpt  = PROJECT_ROOT / "models" / "lstm_fold_1.pth"
assert lstm_ckpt.exists(), f"LSTM checkpoint not found: {lstm_ckpt}"
lstm_model.load_state_dict(torch.load(lstm_ckpt, map_location=device))
lstm_model.eval()
print(f"  LSTM loaded from:  {lstm_ckpt.name}")

# Quick shape sanity check
with torch.no_grad():
    dummy_img   = torch.randn(1, 3, 224, 224)
    dummy_seq   = torch.randn(1, 30, 512)
    emb_out     = feature_extractor(dummy_img)
    lstm_out    = lstm_model(dummy_seq)
print(f"  CNN output shape:  {emb_out.shape}   (expected [1, 512])")
print(f"  LSTM output shape: {lstm_out.shape}   (expected [1, 3])")


# =============================================================================
# POINT 2 – Export CNN feature extractor to ONNX
# =============================================================================
print("\n" + "="*60)
print("POINT 2 – Exporting CNN to ONNX")
print("="*60)

cnn_onnx_path = EXPORT_DIR / "cnn.onnx"

dummy_cnn_input = torch.randn(1, 3, 224, 224)

torch.onnx.export(
    feature_extractor,
    dummy_cnn_input,
    str(cnn_onnx_path),
    opset_version=11,
    input_names=["input_image"],
    output_names=["embedding"],
    dynamic_axes={
        "input_image": {0: "batch_size"},
        "embedding":   {0: "batch_size"},
    },
    do_constant_folding=True,
    verbose=False,
)
print(f"  Saved: {cnn_onnx_path}  ({cnn_onnx_path.stat().st_size / 1e6:.1f} MB)")

# Verify ONNX model
try:
    import onnx
    onnx_model = onnx.load(str(cnn_onnx_path))
    onnx.checker.check_model(onnx_model)
    print("  ONNX CNN check: PASSED")
except ImportError:
    print("  onnx not installed — skipping check (install with: pip install onnx)")


# =============================================================================
# POINT 3 – Export LSTM to ONNX
# =============================================================================
print("\n" + "="*60)
print("POINT 3 – Exporting LSTM to ONNX")
print("="*60)

lstm_onnx_path = EXPORT_DIR / "lstm.onnx"

dummy_lstm_input = torch.randn(1, 30, 512)

torch.onnx.export(
    lstm_model,
    dummy_lstm_input,
    str(lstm_onnx_path),
    opset_version=11,
    input_names=["sequence"],
    output_names=["logits"],
    dynamic_axes={
        "sequence": {0: "batch_size"},
        "logits":   {0: "batch_size"},
    },
    do_constant_folding=True,
    verbose=False,
)
print(f"  Saved: {lstm_onnx_path}  ({lstm_onnx_path.stat().st_size / 1e6:.1f} MB)")

try:
    import onnx
    onnx_model = onnx.load(str(lstm_onnx_path))
    onnx.checker.check_model(onnx_model)
    print("  ONNX LSTM check: PASSED")
except ImportError:
    print("  onnx not installed — skipping check")


# =============================================================================
# POINTS 4 & 5 – Convert ONNX → TFLite with post-training quantisation
# =============================================================================
print("\n" + "="*60)
print("POINTS 4 & 5 – Converting ONNX to TFLite (with quantisation)")
print("="*60)

def convert_onnx_to_tflite(onnx_path: Path, tflite_path: Path, model_name: str):
    """Convert an ONNX model to a quantised TFLite FlatBuffer using onnx2tf or tf.lite."""
    import subprocess
    import shutil

    print(f"\n  Converting {onnx_path.name} -> TFLite...")

    # Method A: Try onnx2tf (modern, robust ONNX -> TFLite converter)
    try:
        out_dir = EXPORT_DIR / f"{model_name}_onnx2tf"
        if out_dir.exists():
            shutil.rmtree(out_dir)

        # Run onnx2tf CLI with float16 / int8 quantisation (Point 5)
        cmd = [
            sys.executable, "-m", "onnx2tf",
            "-i", str(onnx_path),
            "-o", str(out_dir),
            "-qf16"  # Float16 post-training quantisation
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)

        # Look for output .tflite file
        tflite_candidates = list(out_dir.glob("*.tflite"))
        if tflite_candidates:
            best_tflite = tflite_candidates[0]
            shutil.copy(best_tflite, tflite_path)
            size_mb = tflite_path.stat().st_size / 1e6
            print(f"  TFLite saved via onnx2tf: {tflite_path} ({size_mb:.2f} MB)")
            return True
        else:
            print(f"  onnx2tf warning: {res.stderr[:200] if res.stderr else 'no tflite file produced'}")
    except Exception as e:
        print(f"  onnx2tf exception: {e}")

    # Method B: Fallback to onnx-tf + TFLiteConverter
    saved_model_dir = EXPORT_DIR / f"{model_name}_saved_model"
    try:
        from onnx_tf.backend import prepare
        import onnx
        import tensorflow as tf

        onnx_model = onnx.load(str(onnx_path))
        tf_rep = prepare(onnx_model)
        tf_rep.export_graph(str(saved_model_dir))

        converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.target_spec.supported_types = [tf.float16]

        tflite_model = converter.convert()
        tflite_path.write_bytes(tflite_model)
        size_mb = tflite_path.stat().st_size / 1e6
        print(f"  TFLite saved via onnx-tf: {tflite_path} ({size_mb:.2f} MB)")
        return True
    except Exception as e:
        print(f"  onnx-tf fallback error: {e}")
        return False



cnn_tflite_path  = EXPORT_DIR / "cnn.tflite"
lstm_tflite_path = EXPORT_DIR / "lstm.tflite"

cnn_ok  = convert_onnx_to_tflite(cnn_onnx_path,  cnn_tflite_path,  "cnn")
lstm_ok = convert_onnx_to_tflite(lstm_onnx_path, lstm_tflite_path, "lstm")


# =============================================================================
# POINT 6 – Benchmark both models on CPU
# =============================================================================
print("\n" + "="*60)
print("POINT 6 – Benchmarking models on CPU (PyTorch)")
print("="*60)

N_WARMUP = 5
N_BENCH  = 100

# ── CNN benchmark ─────────────────────────────────────────────────────────────
dummy_img = torch.randn(1, 3, 224, 224)
with torch.no_grad():
    for _ in range(N_WARMUP):
        _ = feature_extractor(dummy_img)

times = []
with torch.no_grad():
    for _ in range(N_BENCH):
        t0 = time.perf_counter()
        _ = feature_extractor(dummy_img)
        times.append((time.perf_counter() - t0) * 1000)

cnn_avg = np.mean(times)
cnn_p95 = np.percentile(times, 95)
print(f"  CNN  — avg: {cnn_avg:.1f}ms   p95: {cnn_p95:.1f}ms   (target: <50ms)")
if cnn_avg > 50:
    print("  [WARNING] CNN is above 50ms. On-phone latency will be higher.")
    print("  Consider reducing input to 160x160 if needed on device.")

# ── LSTM benchmark ────────────────────────────────────────────────────────────
dummy_seq = torch.randn(1, 30, 512)
with torch.no_grad():
    for _ in range(N_WARMUP):
        _ = lstm_model(dummy_seq)

times = []
with torch.no_grad():
    for _ in range(N_BENCH):
        t0 = time.perf_counter()
        _ = lstm_model(dummy_seq)
        times.append((time.perf_counter() - t0) * 1000)

lstm_avg = np.mean(times)
lstm_p95 = np.percentile(times, 95)
print(f"  LSTM — avg: {lstm_avg:.1f}ms   p95: {lstm_p95:.1f}ms   (target: <10ms)")

# ── TFLite benchmark (if conversion succeeded) ────────────────────────────────
if cnn_ok and lstm_ok:
    try:
        import tensorflow as tf

        print("\n  TFLite CNN benchmark:")
        interp = tf.lite.Interpreter(model_path=str(cnn_tflite_path))
        interp.allocate_tensors()
        inp  = interp.get_input_details()
        out  = interp.get_output_details()
        dummy_np = np.random.randn(1, 3, 224, 224).astype(np.float32)
        # Warmup
        for _ in range(N_WARMUP):
            interp.set_tensor(inp[0]["index"], dummy_np)
            interp.invoke()
        times = []
        for _ in range(N_BENCH):
            t0 = time.perf_counter()
            interp.set_tensor(inp[0]["index"], dummy_np)
            interp.invoke()
            times.append((time.perf_counter() - t0) * 1000)
        print(f"  TFLite CNN  — avg: {np.mean(times):.1f}ms  p95: {np.percentile(times, 95):.1f}ms")

    except Exception as e:
        print(f"  TFLite benchmark skipped: {e}")


# =============================================================================
# POINT 7 – Save reference normalisation parameters
# =============================================================================
print("\n" + "="*60)
print("POINT 7 – Saving reference normalisation parameters")
print("="*60)

norm_dir = EXPORT_DIR / "norm_params"
norm_dir.mkdir(exist_ok=True)

# Load normalisation from UTA processed embeddings (first dev subject as reference)
uta_emb_dir = PROJECT_ROOT / "processed" / "UTA" / "normalized_embeddings"

if uta_emb_dir.exists():
    # Find first available subject's alert embedding
    for subj_dir in sorted(uta_emb_dir.iterdir()):
        alert_path = subj_dir / "alert.npy"
        if alert_path.exists():
            ref_emb = np.load(alert_path)   # (T, 512)
            ref_mean = ref_emb.mean(axis=0)  # (512,)
            ref_std  = np.maximum(ref_emb.std(axis=0), 1e-2)  # (512,) with floor

            np.save(norm_dir / "mean.npy", ref_mean.astype(np.float32))
            np.save(norm_dir / "std.npy",  ref_std.astype(np.float32))
            print(f"  Saved mean.npy and std.npy from subject: {subj_dir.name}")
            print(f"  mean range: [{ref_mean.min():.4f}, {ref_mean.max():.4f}]")
            print(f"  std  range: [{ref_std.min():.4f},  {ref_std.max():.4f}]")
            break
else:
    # Compute from dummy embeddings as placeholder for testing
    print("  UTA embeddings not found — saving dummy norm params for testing")
    np.save(norm_dir / "mean.npy", np.zeros(512, dtype=np.float32))
    np.save(norm_dir / "std.npy",  np.ones(512,  dtype=np.float32))
    print("  [NOTE] Replace with real stats before app testing!")


# =============================================================================
# SUMMARY
# =============================================================================
print("\n" + "="*60)
print("EXPORT SUMMARY")
print("="*60)
print(f"  ONNX files  -> {EXPORT_DIR}")
for p in sorted(EXPORT_DIR.glob("*.onnx")):
    print(f"    {p.name:25s}  {p.stat().st_size / 1e6:.2f} MB")

print(f"\n  TFLite files -> {EXPORT_DIR}")
for p in sorted(EXPORT_DIR.glob("*.tflite")):
    print(f"    {p.name:25s}  {p.stat().st_size / 1e6:.2f} MB")

print(f"\n  Norm params  -> {norm_dir}")
for p in sorted(norm_dir.glob("*.npy")):
    print(f"    {p.name}")

print("\nDone. Next: install Flutter and run flutter create drowsiness_app")
