from torch.utils.data import Dataset
from PIL import Image

class DrowsinessDataset(Dataset):
    def __init__(self, dataframe, transform=None):
        self.df = dataframe.reset_index(drop=True)
        self.transform = transform

        self.label_map = {
            "alert": 0,
            "drowsy": 1
        }

    def __len__(self):
        return len(self.df)

    def __getitem__(self, idx):
        row = self.df.iloc[idx]

        image = Image.open(row["filepath"]).convert("RGB")

        if self.transform:
            image = self.transform(image)

        label = self.label_map[row["label"]]

        return image, label