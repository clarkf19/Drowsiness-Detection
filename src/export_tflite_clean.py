"""
Converts CNN (EfficientNet-B0 feature extractor) and LSTM sequence classifier
to standard, native TFLite FlatBuffers for Flutter mobile inference.
"""

import sys
import shutil
from pathlib import Path
import numpy as np
import torch
import torch.nn as nn
from torchvision import models
import tensorflow as tf
import onnx2tf

PROJECT_ROOT = Path(__file__).parent.parent
sys.path.append(str(PROJECT_ROOT))
from src.lstm_model import DrowsinessLSTM

MODELS_DIR = PROJECT_ROOT / "models"
CKPT_DIR = MODELS_DIR / "checkpoints"
TFLITE_DIR = MODELS_DIR / "tflite"
FLUTTER_ASSETS = PROJECT_ROOT / "flutter_app" / "assets" / "models"

TFLITE_DIR.mkdir(parents=True, exist_ok=True)
FLUTTER_ASSETS.mkdir(parents=True, exist_ok=True)

# =============================================================================
# STEP 1: CNN Feature Extractor -> TFLite ([1, 3, 224, 224] -> [1, 512])
# =============================================================================
print("\n" + "=" * 60)
print("STEP 1: Converting CNN Feature Extractor to TFLite")
print("=" * 60)

cnn_final_tflite = TFLITE_DIR / "cnn_final" / "cnn_float32.tflite"
if not cnn_final_tflite.exists():
    # Build CNN Feature Extractor
    cnn_full = models.efficientnet_b0(weights=None)
    cnn_full.classifier = nn.Sequential(
        nn.Dropout(0.3),
        nn.Linear(1280, 512),
        nn.ReLU(),
        nn.Dropout(0.3),
        nn.Linear(512, 3),
    )
    cnn_ckpt = CKPT_DIR / "best_cnn_3class.pth"
    cnn_full.load_state_dict(torch.load(cnn_ckpt, map_location="cpu"))
    cnn_full.eval()

    feature_extractor = nn.Sequential(
        cnn_full.features,
        cnn_full.avgpool,
        nn.Flatten(),
        cnn_full.classifier[0],
        cnn_full.classifier[1],
        cnn_full.classifier[2],
    )
    feature_extractor.eval()

    cnn_onnx_path = TFLITE_DIR / "cnn.onnx"
    dummy_cnn_in = torch.randn(1, 3, 224, 224)
    torch.onnx.export(
        feature_extractor,
        dummy_cnn_in,
        str(cnn_onnx_path),
        input_names=["input_image"],
        output_names=["embedding"],
        dynamic_axes={
            "input_image": {0: "batch_size"},
            "embedding": {0: "batch_size"},
        },
        do_constant_folding=True,
        verbose=False,
    )

    cnn_final_dir = TFLITE_DIR / "cnn_final"
    onnx2tf.convert(
        input_onnx_file_path=str(cnn_onnx_path),
        output_folder_path=str(cnn_final_dir),
        keep_ncw_or_nchw_or_ncdhw_input_names=["input_image"],
        copy_onnx_input_output_names_to_tflite=True,
        not_use_onnxsim=True,
    )

shutil.copy(cnn_final_tflite, TFLITE_DIR / "cnn.tflite")
shutil.copy(cnn_final_tflite, FLUTTER_ASSETS / "cnn.tflite")
print(f"  CNN TFLite copied -> {FLUTTER_ASSETS / 'cnn.tflite'} ({cnn_final_tflite.stat().st_size / 1e6:.2f} MB)")


# =============================================================================
# STEP 2: LSTM Model -> Standard Unrolled Keras -> Pure TFLite
# =============================================================================
print("\n" + "=" * 60)
print("STEP 2: Converting LSTM to Native Built-in TFLite")
print("=" * 60)

pt_lstm = DrowsinessLSTM()
pt_lstm.load_state_dict(torch.load(MODELS_DIR / "lstm_fold_1.pth", map_location="cpu"))
pt_lstm.eval()

def get_keras_lstm_weights(w_ih, w_hh, b_ih, b_hh):
    w_ih_np = w_ih.numpy().T
    w_hh_np = w_hh.numpy().T
    bias_np = (b_ih + b_hh).numpy()
    return [w_ih_np, w_hh_np, bias_np]

sd = pt_lstm.state_dict()
l0_weights = get_keras_lstm_weights(sd['lstm.weight_ih_l0'], sd['lstm.weight_hh_l0'], sd['lstm.bias_ih_l0'], sd['lstm.bias_hh_l0'])
l1_weights = get_keras_lstm_weights(sd['lstm.weight_ih_l1'], sd['lstm.weight_hh_l1'], sd['lstm.bias_ih_l1'], sd['lstm.bias_hh_l1'])

bn_gamma = sd['bn.weight'].numpy()
bn_beta  = sd['bn.bias'].numpy()
bn_mean  = sd['bn.running_mean'].numpy()
bn_var   = sd['bn.running_var'].numpy()

fc_w = sd['fc.weight'].numpy().T
fc_b = sd['fc.bias'].numpy()

# Static unrolled LSTM for 100% native standard TFLite ops
inp = tf.keras.Input(shape=(30, 512), batch_size=1, name="sequence")
x = tf.keras.layers.LSTM(64, return_sequences=True, unroll=True, name="lstm_l0")(inp)
x = tf.keras.layers.LSTM(64, return_sequences=False, unroll=True, name="lstm_l1")(x)
x = tf.keras.layers.BatchNormalization(epsilon=1e-5, name="bn")(x)
out = tf.keras.layers.Dense(3, name="logits")(x)

k_model = tf.keras.Model(inputs=inp, outputs=out)
k_model.get_layer("lstm_l0").set_weights(l0_weights)
k_model.get_layer("lstm_l1").set_weights(l1_weights)
k_model.get_layer("bn").set_weights([bn_gamma, bn_beta, bn_mean, bn_var])
k_model.get_layer("logits").set_weights([fc_w, fc_b])

# Validate numerical accuracy vs PyTorch
np.random.seed(42)
test_seq = np.random.randn(1, 30, 512).astype(np.float32)
with torch.no_grad():
    pt_logits = pt_lstm(torch.from_numpy(test_seq)).numpy()
k_logits = k_model(test_seq, training=False).numpy()
max_err = np.max(np.abs(pt_logits - k_logits))
print(f"  LSTM PyTorch vs Keras diff: {max_err:.6e}")
assert max_err < 1e-4, f"Mismatch: {max_err}"

# Convert to TFLite
converter = tf.lite.TFLiteConverter.from_keras_model(k_model)
lstm_tflite_bytes = converter.convert()

lstm_tflite_path = TFLITE_DIR / "lstm.tflite"
lstm_tflite_path.write_bytes(lstm_tflite_bytes)

lstm_flutter_path = FLUTTER_ASSETS / "lstm.tflite"
lstm_flutter_path.write_bytes(lstm_tflite_bytes)
print(f"  LSTM TFLite saved -> {lstm_flutter_path} ({len(lstm_tflite_bytes) / 1e6:.2f} MB)")


# =============================================================================
# STEP 3: Complete Verification with TFLite Interpreter
# =============================================================================
print("\n" + "=" * 60)
print("STEP 3: Complete TFLite Interpreter Verification")
print("=" * 60)

interp_cnn = tf.lite.Interpreter(model_path=str(FLUTTER_ASSETS / "cnn.tflite"))
interp_cnn.allocate_tensors()
cnn_in = interp_cnn.get_input_details()
cnn_out = interp_cnn.get_output_details()
print(f"  CNN Input Tensor:  shape={cnn_in[0]['shape'].tolist()} dtype={cnn_in[0]['dtype'].__name__}")
print(f"  CNN Output Tensor: shape={cnn_out[0]['shape'].tolist()} dtype={cnn_out[0]['dtype'].__name__}")

interp_lstm = tf.lite.Interpreter(model_path=str(FLUTTER_ASSETS / "lstm.tflite"))
interp_lstm.allocate_tensors()
lstm_in = interp_lstm.get_input_details()
lstm_out = interp_lstm.get_output_details()
print(f"  LSTM Input Tensor:  shape={lstm_in[0]['shape'].tolist()} dtype={lstm_in[0]['dtype'].__name__}")
print(f"  LSTM Output Tensor: shape={lstm_out[0]['shape'].tolist()} dtype={lstm_out[0]['dtype'].__name__}")

# Check TFLite magic header
for name, p in [("CNN", FLUTTER_ASSETS / "cnn.tflite"), ("LSTM", FLUTTER_ASSETS / "lstm.tflite")]:
    with open(p, "rb") as f:
        magic = f.read(8)
        is_tflite = (magic[4:8] == b"TFL3")
        print(f"  {name} valid TFL3 header: {is_tflite}")

print("\nSUCCESS! Native TFLite models are ready in flutter_app/assets/models/.")
