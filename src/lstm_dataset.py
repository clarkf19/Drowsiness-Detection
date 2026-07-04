import numpy as np
import torch
from torch.utils.data import Dataset


class LSTMDataset(Dataset):

    def __init__(
        self,
        dataframe,
        window_size=30
    ):
        self.df = dataframe.reset_index(drop=True)
        self.window_size = window_size

    def __len__(self):
        return len(self.df)

    def __getitem__(self, idx):

        row = self.df.iloc[idx]

        emb = np.load(
            row["embedding_path"]
        )

        start = row["start_idx"]

        x = emb[
            start:
            start + self.window_size
        ]

        y = row["label"]

        x = torch.tensor(
            x,
            dtype=torch.float32
        )

        y = torch.tensor(
            y,
            dtype=torch.long
        )

        return x, y