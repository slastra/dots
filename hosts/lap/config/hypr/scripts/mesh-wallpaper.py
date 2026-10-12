#!/usr/bin/env python3
# Renders the still wallpaper (walls/mesh.png): a Rosé Pine mesh gradient,
# shown by hyprpaper whenever hyprglaze is off. Usage: mesh-wallpaper.py OUT.png
import subprocess, sys
base=(0x19,0x17,0x24)
C={'pine':(0x31,0x74,0x8F),'iris':(0xC4,0xA7,0xE7),'love':(0xEB,0x6F,0x92),'foam':(0x9C,0xCF,0xD8),'overlay':(0x26,0x23,0x3A)}
def mix(c,t): return '#%02x%02x%02x'%tuple(round(b+(x-b)*t) for b,x in zip(base,c))
W,H=360,225
pts=[(0.08,0.12,mix(C['iris'],.30)),(0.88,0.08,mix(C['pine'],.55)),(0.52,0.50,mix(C['overlay'],.6)),
     (0.12,0.92,mix(C['pine'],.38)),(0.92,0.88,mix(C['love'],.26)),(0.60,0.98,mix(C['iris'],.16)),
     (0.40,0.10,mix(C['overlay'],.4)),(0.97,0.45,mix(C['foam'],.12)),(0.02,0.50,mix(base,0))]
sp=' '.join(f'{x*W:.0f},{y*H:.0f} {c}' for x,y,c in pts)
out=sys.argv[1]
subprocess.run(['magick','-size',f'{W}x{H}','xc:','-define','shepards:power=2.2','-sparse-color','Shepards',sp,
  '-blur','0x18','-depth','16','-filter','Lanczos','-resize','2880x1800!',
  '-attenuate','0.35','+noise','Gaussian','-depth','8',out],check=True)
