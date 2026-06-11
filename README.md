# Early Drowsiness Detection System

CNN-LSTM based driver drowsiness prediction using NTHU-DDD, UTA-RLDD and Mendeley datasets.

## Project Overview

Drowsy driving is one of the leading causes of road accidents worldwide. Most existing systems detect drowsiness only after the driver's eyes have already closed. This project aims to predict drowsiness before complete eye closure by analyzing temporal changes in facial features.

The system uses a hybrid CNN-LSTM architecture:

* CNN extracts facial features from individual video frames.
* LSTM learns how these features evolve over time.
* The model predicts declining alertness before the driver falls asleep.

## Datasets

### NTHU-DDD

* Image-based dataset
* Multiple drowsiness conditions
* Glasses / no glasses
* Yawning, blinking, sleepy combinations

### UTA-RLDD

* Real-world driving videos
* Alert, low vigilant and drowsy states
* Multiple drivers and environmental conditions

### Mendeley Drowsiness Dataset

* Additional training and testing samples
* Used for model validation and robustness testing

## Project Structure

```text
drowsiness_project/
├── datasets/
├── src/
├── notebooks/
├── models/
├── results/
├── README.md
└── requirements.txt
```

## Model Pipeline

1. Dataset preprocessing
2. Frame extraction from videos
3. Facial feature extraction
4. CNN training
5. LSTM sequence learning
6. Evaluation
7. TFLite conversion
8. Mobile deployment

## Team

SPIT Engineering Project

## Future Work

* Real-time Android application
* Early drowsiness prediction
* On-device inference using TensorFlow Lite
* Research paper publication
