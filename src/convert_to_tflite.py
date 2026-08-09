"""
Standalone TFLite conversion script.
Run this with SYSTEM Python (not the project venv) to avoid dependency conflicts.

Usage (run from project root in a NEW terminal):
  python src/convert_to_tflite.py

Installs into a temporary virtual environment, converts both ONNX models to TFLite,
then copies the outputs into:
  models/tflite/cnn.tflite
  models/tflite/lstm.tflite
  flutter_app/assets/models/cnn.tflite
  flutter_app/assets/models/lstm.tflite
"""

import subprocess
import sys
import venv
import shutil
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
ONNX_DIR     = PROJECT_ROOT / "models" / "tflite"
OUT_DIR      = PROJECT_ROOT / "models" / "tflite"
FLUTTER_ASSETS = PROJECT_ROOT / "flutter_app" / "assets" / "models"
VENV_DIR     = PROJECT_ROOT / ".tflite_venv"

CNN_ONNX  = ONNX_DIR / "cnn.onnx"
LSTM_ONNX = ONNX_DIR / "lstm.onnx"

assert CNN_ONNX.exists(),  f"Missing: {CNN_ONNX}"
assert LSTM_ONNX.exists(), f"Missing: {LSTM_ONNX}"

# ── Step 1: Create isolated venv ──────────────────────────────────────────────
print("\n[1/4] Creating isolated venv at .tflite_venv ...")
if VENV_DIR.exists():
    shutil.rmtree(VENV_DIR)
venv.create(str(VENV_DIR), with_pip=True)

pip_exe = str(VENV_DIR / "Scripts" / "pip.exe")
py_exe  = str(VENV_DIR / "Scripts" / "python.exe")

# ── Step 2: Install onnx2tf + tensorflow in clean env ─────────────────────────
print("\n[2/4] Installing onnx2tf and tensorflow in isolated venv ...")
pkgs = ["onnx2tf", "tensorflow-cpu", "onnx"]
res = subprocess.run([pip_exe, "install"] + pkgs, check=True)

# ── Step 3: Run conversion ────────────────────────────────────────────────────
print("\n[3/4] Converting ONNX models to TFLite ...")

convert_script = """
import onnx2tf, shutil, pathlib

OUT = pathlib.Path(r'{out_dir}')

def convert(onnx_path, name):
    out_folder = OUT / f'{{name}}_onnx2tf'
    onnx2tf.convert(
        input_onnx_file_path=str(onnx_path),
        output_folder_path=str(out_folder),
        not_use_onnxsim=False,
    )
    tflite_files = list(out_folder.glob('*.tflite'))
    if not tflite_files:
        raise RuntimeError(f'No .tflite file produced for {{name}}')
    dst = OUT / f'{{name}}.tflite'
    shutil.copy(tflite_files[0], dst)
    print(f'  Saved: {{dst}}  ({{dst.stat().st_size/1e6:.2f}} MB)')
    return dst

convert(r'{cnn}', 'cnn')
convert(r'{lstm}', 'lstm')
print('Conversion complete!')
""".format(
    out_dir=str(OUT_DIR),
    cnn=str(CNN_ONNX),
    lstm=str(LSTM_ONNX),
)

subprocess.run([py_exe, "-c", convert_script], check=True)

# ── Step 4: Copy to Flutter assets ───────────────────────────────────────────
print("\n[4/4] Copying TFLite models to Flutter assets ...")
FLUTTER_ASSETS.mkdir(parents=True, exist_ok=True)

for model in ["cnn.tflite", "lstm.tflite"]:
    src = OUT_DIR / model
    dst = FLUTTER_ASSETS / model
    if src.exists():
        shutil.copy(src, dst)
        print(f"  Copied {model} -> flutter_app/assets/models/")
    else:
        print(f"  WARNING: {model} not found in {OUT_DIR}")

print("\nAll done! TFLite models ready for Flutter.")
print(f"  models/tflite/cnn.tflite")
print(f"  models/tflite/lstm.tflite")
print(f"  flutter_app/assets/models/cnn.tflite")
print(f"  flutter_app/assets/models/lstm.tflite")
