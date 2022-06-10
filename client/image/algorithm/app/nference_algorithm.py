#!/usr/bin/env python

import sys
import os
import json
import torch
import argparse
import torch.multiprocessing as mp
from torch.utils.data import DataLoader, Dataset
import torch.nn as nn
import random
from sklearn import metrics
import numpy as np
import pathlib
import pandas as pd
import base64
import torchaudio
import torchvision
from scipy import interpolate


outputdir  = ''

torch.manual_seed(64)
random.seed(64)

class DS(Dataset):
    def __init__(self, data_dir):
        super(DS, self).__init__()

        df = pd.read_csv(os.path.join(data_dir, 'test.csv'), sep='|')

        self.data_list = []
        for f in pathlib.Path(data_dir).glob('*.npz'):
            filepath = str(f)
            self.data_list.append(np.load(filepath)['x'])

    def __len__(self):
        return len(self.data_list)

    def __getitem__(self, index):
        return self.data_list[index]

def interpolate_signal(y):
    x = np.arange(0, y.shape[1], 1)
    result = []
    for y_ in y:
        f = interpolate.interp1d(x, y_, kind="cubic")
        x_new = np.arange(0, y.shape[1] - 0.5, 0.5)
        y_new = f(x_new)
        y_new = np.append(y_new, [0])
        result.append(np.expand_dims(y_new, axis=0))

    result = np.concatenate(result, axis=0)
    return result

class FeatherDS(Dataset):
    def __init__(self, file_name):
        super().__init__()
        self.required_size = 5000
        self.df = pd.read_feather(file_name)

    def __len__(self):
        return len(self.df)

    def __getitem__(self, index):
        x = self.df.loc[index, "X"].reshape(-1, 12).T
        if x.shape[1] != self.required_size:
            x = interpolate_signal(x)
        return x


class Model(nn.Module):
    def __init__(self):
        super(Model, self).__init__()
        self.net1 = nn.Sequential(
            nn.Conv1d(12, 16, kernel_size=3),
            nn.BatchNorm1d(16),
            nn.ReLU(inplace=True)
        )

        self.net2 = nn.AdaptiveAvgPool1d(output_size=1)
        self.net3 = nn.Sequential(
            nn.Linear(16, 4),
            nn.Dropout(0.5),
            nn.Linear(4, 1)
        )

    def forward(self, x):
        x = self.net1(x)
        x = self.net2(x)
        x = x.squeeze(dim=-1)
        x = self.net3(x)

        x = torch.cat([x, x], dim=-1)

        return x


class Net(object):
    def __init__(self, args):
        super(Net, self).__init__()
        self.args = args
        #self.device = torch.device('cuda')
        self.device = torch.device('cpu')
        self.model = Model()
        params = list(self.model.parameters())
        self.optimizer = torch.optim.AdamW(params=params, lr=1e-5)
        self.loss = nn.MSELoss()

        self.model = self.model.to(self.device)
        self.loss = self.loss.to(self.device)
        self.tx_spectrogram = torchaudio.transforms.Spectrogram(n_fft=128, hop_length=64)
        self.tx_spectrogram = self.tx_spectrogram.to(self.device)

    def t(self):
        self.model.train()
        x = torch.rand(24, 12, 3000)
        x = x.to(self.device)
        s = self.tx_spectrogram.forward(x)
        y = self.model(x)
        yt = torch.zeros(24, 2)
        yt = yt.to(self.device)
        l = self.loss(y, yt)
        l.backward()
        self.optimizer.step()
        self.optimizer.zero_grad()
        lval = l.detach().cpu().item()
        print(lval)
        yt = yt.detach().cpu().numpy()
        y = y.detach().cpu().numpy()
        y = torch.zeros(24, 2)
        print(yt)
        print(y)
        val = metrics.accuracy_score(yt, y)
        print(val)
        print('Save model')
        torch.save(self.model.state_dict(), outputdir + '/' +  'test_model.ckpt')
        m = {
            'loss' : lval,
            'acc' : val
        }

        print ("writing to file at " + outputdir + "the value in m " + json.dumps(m, indent=4))
        fh = open(outputdir + '/' +'test_metrics.json', 'w')
        fh.write(json.dumps(m, indent=4))
        fh.close()

    def e(self):
        with torch.no_grad():
            print('Load model')
            self.model.load_state_dict(torch.load('test_model.ckpt'))
            self.model.eval()

            x = torch.rand(24, 12, 3000)
            x = x.to(self.device)
            y = self.model(x)
            yt = torch.rand(24, 2)
            yt = yt.to(self.device)
            l = self.loss(y, yt)
            lval = l.detach().cpu().item()
            print(lval)

    def run(self):
        if self.args.mode == 'train':
            self.t()
        else:
            self.e()

def main():
    global outputdir
    mp.set_start_method('spawn')
    parser = argparse.ArgumentParser(description='Simple Net')

    parser.add_argument('--data-dir', action='store', dest='data_dir',
                        default='/algorithm-input', type=str, help='Data dir')
    parser.add_argument('--mode', action='store', dest='mode',
                        default='train', type=str, help='Train or Test')

    parser.add_argument('--output', action='store', dest='out_dir',
                        default='/algorithm-output', type=str, help='Output dir')


    args = parser.parse_args(sys.argv[1:])

    inputdir = args.data_dir
    outputdir = args.out_dir

    print ("Running ML Algorithm..")
    print ("Input Directory is "+inputdir)
    print ("Output Directory is "+outputdir)
    ds = DS(args.data_dir)
    # Luke changing num_workers from 10 to 1
    data_loader = DataLoader(ds, 64, shuffle=True, num_workers=0)
    for item in data_loader:
        print(item.shape)

    fds = FeatherDS(os.path.join(args.data_dir, 'train_0_50.feather'))
    # Luke changing num_workers from 10 to 1
    fdl = DataLoader(fds, 128, shuffle=True, num_workers=0)
    for item in fdl:
        print(item.shape)

    net = Net(args)
    net.run()

if __name__ == '__main__':
    main()
