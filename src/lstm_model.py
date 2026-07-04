import torch
import torch.nn as nn


class DrowsinessLSTM(nn.Module):
    def __init__(self):
        super().__init__()

        self.lstm = nn.LSTM(
            input_size=512,
            hidden_size=64,
            num_layers=2,
            dropout=0.5,
            batch_first=True
        )

        self.bn = nn.BatchNorm1d(64)

        self.dropout = nn.Dropout(0.5)

        self.fc = nn.Linear(
            64,
            3
        )

    def forward(self, x):

        out, _ = self.lstm(x)

        out = out[:, -1, :]

        out = self.bn(out)

        out = self.dropout(out)

        out = self.fc(out)

        return out