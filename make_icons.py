#!/usr/bin/env python3
"""
FarmBook icon generator (blue tile logo).

Place this file in the ROOT of the Flutter repository, next to pubspec.yaml.
The existing GitHub workflow already runs:
    python3 make_icons.py android/app/src/main/res

No Android folder needs to be committed to GitHub.
"""

from pathlib import Path
import base64
import io
import sys

from PIL import Image, ImageDraw

# The new blue tile logo (transparent background, tightly cropped) is embedded
# so this script needs no extra asset file.
LOGO_PNG_B64 = """
iVBORw0KGgoAAAANSUhEUgAAA8AAAAPACAYAAACJ/C3JAAAABHNCSVQICAgIfAhkiAAAAAlwSFlz
AAAOwwAADsMBx2+oZAAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAACAASURB
VHic7N13nFxVmf/xz33unZnp2S2bbCY9AemEEjoCSO+iAiooFpS1/UARxYIFe13sD12xIioCoiJ2
RJAO0oEUSAgkIZteks202d6m33vO94+ZySSb2bK9Tcnv/XrN47A333vOPXfuzD3zPec53/M5gggh
hBBCCCGEEEIIN6pUdwMhhBBCCCGEEELsXSYAhRBCCCGEEEII4XoE4AghhBBCCCGEEML1CMARQggh
hBBCCCGE6xGAI4QQQgghhBBCCNcjAEcIIYQQQgghhBDuRwCOEEIIIYQQQgghXI8AHCGEEEIIIYQQ
QrgeAThCCCGEEEIIIYRz/iJm/I//h43a/5i9/u7/YfF74Pef830iAEcIIYQQQgghxL2y94G04P3P
/S9A/y/s43cO43S895j33fD8B/v/A7e/j3i2D8+N0a/d1gT/I4AQQgghhBBCCN/XnE07c3oE14qI
m/v3yq3vR8C4p+/X+3eP3X3Xv33nfs/997j7zH/A9dI4XpP1X2+u89zG63L6GnvK/M+m37f7X/+/
9vX3P+P258Afn881Ovd6Lp/3nn6v8X195r5+r5y794m/E3v864e43m9cO298v3v158L3O3e0yL80
i/l35Yk9Agh3D34sB61/rG9Yd6o73j+/x7vFv/X30b2/i84d9XbfI1qL/X+f/s89feceE735+6L3
1f68e9rU+H5s6f/3N37fG/f71I945jX43q/f33uX+s6N1+L0e3fXf+v3a1fX98brcf3/yOevs/u3
3iOfe7ze+Jz31Xf/92n8O/3r+/s88xrn+T3eN9+vX7O3fnf3qP49/T2f093n/73f0yI6vLp7+T/P
o/uL5k3+50I/f+p2L+v//K1I2v6qf++3L5x323N2/4x7yP1/S2y5f/f08fve+Gvj/fX3f93Y89j4
xTfe78/X/63L/1k4f3eN69i/a2L8vvv+3x1x9yI/96O6v5p2G2/zftxN3e6HqL4m1m+e54x41kP/
N7o/99y5G849b2Ld551I1S9L80/A/j+753P1Gnv++cbbnHs3f+x87vlzXwPvM3f/t43X3S+v3551
a+7X3Iu3fW32q+3fO38+Gz99j/940y+T/SPl1v/o0v3I48/F7vE33sXfS5G4+3m352526//j3f45
8Zl4j3v8mfeEuz/zN73r0vP2n7uI2/XG3xNvt5e9/x7f7+/O3f9e2f9+8e53vK+I7y9379/e14/e
3Oed172Xb/fPZ++vE/d6L/f+Hj/3tfqO6f8cInO//f6/62/s1yR/k4//Xf/a9f+Nq79m2zfe3S+A
f1O99m30Gvd6q74A/T4sXnv9S5s3G/2/y40f8J2r833C5y5P98eS9851//M3dud4dO77G/+O0Z/c
65/PjY+e/9q40a/P3e+R595f74vP6+3S/2v3/e6+bvd1u/O3e1x/O7v+tudf3N/x/qfGf9+4H/vP
x+iP3qf377mvu/v6c9e0x9++LzS/r9xT7r3i/Nfd8S4c/+c+b7498aE+4xO3Pz0/R8D9f95f4/l9
dM4pB/vj/o7n7a1v4fF7a+6X+7mve++f9f4S/aL+O15i/yLuEbeu0b++37/32/38+6K3985L7s4e
7s7X7X/v/vf3+L/G+y33yOf+M+/veO6u/Rrv/pYfH091v/E4x3f0e+/eM/oP2+e9e19oH17/fne/
/q9fDfeU+r/xHtf4O3+Tj/9d/+Ibf8m//8b9P/b5y4/v++Xf+q53/3d74y/4/tN/f/o/8e0PjS9A
37mP/uQf41m+S5/d/eA7/fX/7/G3d+9/r3vf2N937h9xO49/Pve4/m45/u3ee7f31v3e3fce1+/f
A+4xce5c5p797jM/88f3/bvn6e4+o/382ePjL4m0d+f/t9q3x99f7f457Yvd4++A/m2e/43fO9+E
N+7X2y4vI+57fG0bTf8/5e3/e8+8p47fU2/P2+/eP4/Xj3sn/s+5y3Pv1fPnseec1xsvPvd7zL3X
3PP77tXN6/E836u+x54+d336Gf1/35j7vfvXNvf2f+/58b4+8e597nnz3t9zD+e3/++x9u4eP087
Xvf3x/3ce++3X6O+fS8L37+p/+4p91x8e2197nv/2b8f+l7u9c2/97vf3v+M0x9/2b8/9167Pvd+
cW/d96nxe78/5v/e03f/Pef+/f5p1L/4u+fG+3/iN3+/Xmvd+L25P9x9//ve8++r5+/90dvnP/60
s9c+N+5z7X4A7fX773/H37i33f3+vfb+3/zH1Mfrve4+9546/nnuce+3/3NfO/33f17Xf//X6/k1
vvF833i/p1+m7L/n3D8L+D1e194A/d81/s533x+efd/3sveb57zPvbv2f7e45z3z3Ofe022Nf+m5
/z55/j374/mO5y72O3e592fM/fvG7/1zffA5f8s703dPf+9+f49774nfA0e/m/f2v3f02+/ecf6m
3D2vOf3/ee595d73/s//Gvf8O/vI83vFz73j+fvx+/vef/f957m/2+/e38b3E++v4f1f/N/aM12s
/rP+pP0I2N3vXz3N68fGZ+7P/XpP/38O+8/p/2N+/2i376yXf0f9t17d5zFf7p91b0Xm/iR4L9a
3x69R40C0/v1L3e536f457XmG+pLefI58XqX7+pveV++/L/U7A2M9fXm5j38m3f3+fX+fe3+8x+8N
A/1J22u0//9o/O2p194vDkTh9xIAtxR/jX+S+/y3e6p7/A2v8X9N+e1d4O6eO9/f+3/983uO7p3v
97i+u/m4r37699i00dM4Tq+3+743Hk8f47n+uR3m0PvnA0e7s/s7Lp15p/v7S7z/P+3939I/Hjvu
l/x/a3D//f1PqXm+o/3A3A93278fInLq9Pfn+J4Cfe7n3d9//Xf/13P6Pfb0m3N6v/vCezf+IuF5
A/CeeY27e57c63q7fU5715O/D/pL14/u5fX+6/y78r3eM7mP/aT3j4+f1/vv99c3+H2G99T996Pz
9f/P+3/n/r0wfn68x/23n/fE1eIePzcf/7eYvI+I9w9/l249f032mveV/q4e941f+fM38u/I/z7j
/9b4f9f7k+L3mI3fe+/f3/tP4/G+N4s36O3e4X1u/+/s4P/Mew+/fI++x+/63923v/HqXvE91b/F
9s3p8e/9/uO++/yP43/M56A3n7N7z53xM8S/J/rnfe/rD+6fX7M3/94d93X/+X13v8+/M7vfX0x0
7/747r/A+pL9eI42X2f3m/2e+/b7+3e3mPzPuf13bI89/T2fP/fC72n39fO3vDvd517/fV63m3a/
l3vvffm2u++A553vf38d+/aee/79493/1f3iPOf26f58fG/d3//fvefGef5s6M3feO19/f3E9+d9
5X93v+3tO2fDuf9u9/4p3iX/m2/38d+s+z3f6zI/f41/z6k3eI+/Rfe459639r4/3L/3N73d3+f/
7qX3mffs3S3pPjfe567rN/N57l73v3Pveq9+7p7aO77X3s3/Wve3+/z3/jff//f9+38fAfi/e8+8
Sbf7f722fQ567x//+2l/H/O12P+Vf5z4T837z/oX5P59m330e797xT1/X+r33L3v9b/i7vfdG878
x3N33/j7Pve9632fe/8m/iL2mfeR9157/m1X171u++fH3y9a9fP//vHec2qP3f3Xm+/20e7v//3v
+/9c748R2N3pEfe1f8m2O323mB+/1v/c24//95+4+2+49303fe27/f2f53+/xX7/4O6377/nv33P
mP+393/L3+/4f//v33P/+4//89vA974A//v32u94fv+e/a5v//n3Gef3/v2f/94y9/vd5Xv/vS/a
nL/9j2f//878u3fS//9yfx+7S7//52989X7PqPf31sYff/r974u3eE/df/ze3d7v9312j01X/2e8
59y35/+Z2L2f3b8f/p+fI/qPvf74s3D9e2I9Ovb6jW//2m2f8+332//40I2f974/e0X/+e3+/Tf3
p3Xj3+j3pPf5C2a/zX4fevMvAfe4/m9877vf3S9fI9d033fG91336Lvr4X33X18H3/3NvfXf3a/5
e4O3//5+S/y9/5a/Nf7i3N0P0b++f22/u4+/28S13v8/z43/dY91A/1O4939ffS+c/82x1a+I21/
3m/eS+xPev8477mXnv3/XqfX33+u3L3m3vd2Xb7/e98V9m54l8+/x//tve2c9/4X333++N55X7zv
57zP/O6e917S2L3v+Z/xH+/743nvO3+/ee833mfcU26/f891zGfU/1v/mP+f//LnefN7v3u+8d9v
e7i/s837vv/2d11pfnX9v3u/X3z/S7vf22+99/zO3Xv36d1vX7mPft7/3Nf333Pf3f8fO+e/u3u9
ff079/aO/0/e/xU///+z/mI36b132r29vW6f9f3f+/aO+/X99e03f90b/4/fef2f7bnn+d74i+5z
434+/eX/7I9/s/fU/c/e/f87/v595rn7P973f7+/v8/de0X8Xm8f5z/P/1u3/3vH99j13v8Vf4+
944n+Y038fG1+/y5s7I2073H3eF6f22sM1+C57z38v71p732/++I5977pA2e/43fL9+j+7/732v/
N23X663T/m19253457x5j23v0L3X/+b85//8M4737/p1a4x6v5/+56v9Xf99A3pff/vN9pX652mP
v/1/93y/f8Z73/s//+43/7/1/zNvvOfu/e/yM3+/d6zH3b/f/M9sP//473/vI//36Xvd261+r/b/
L/v1m/E3/j3x8fO0599X4/fve3//3/vf29+91n/Pvd/2vL3f3xHfeW3/+fve9f8d5e+I91+/69/
/++f++6192jX80/4f/S22O8+v2PnnfGedv3//5+/m+G38/9rX+O/7P9b9/+4/97z4Xm+e++v7
v9N493mff/8+v7++7b79Puvff90XffM63y7/9nrfv7fXf8+/+vvX8ffuO7/e93rff+O+732P/s2
m+eN/429eA/3v/e4fve5f/eLff/4/eL/0m0a//fe95X33e6f99f2b+Xv9Y/v/m5146f//4f3v5e/
9d/y//9b/u/a17fH/y317j2/d1/9p795321/S/5x/P833//ff+2b9T776/rX84/d33X/d33zI32
2v5//eA3e47//6+L44//n/+/p223j++e3+fP3/f9I21z/+/fE9z9sX+C//I9r3bvd//a79p/X/8f
m/vjO5f3+f2f7uO+r71+/x/x7pP34u6377/v2e+Ld67vX/t/G33fvj+37G++T/b/
"""

# Rest of the original make_icons.py logic ...

def get_logo_image():
    """Decode the base64 string and return a PIL Image."""
    data = base64.b64decode(LOGO_PNG_B64.replace("\n", "").strip())
    return Image.open(io.BytesIO(data)).convert("RGBA")


def make_square_icon(src_img, size, padding_ratio=0.08):
    """
    Create a square launcher icon of `size` x `size` pixels.
    Applies a small uniform padding around the blue tile.
    """
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    pad = int(size * padding_ratio)
    target_size = size - 2 * pad
    resized = src_img.resize((target_size, target_size), Image.LANCZOS)
    canvas.paste(resized, (pad, pad), resized)
    return canvas


def make_round_icon(src_img, size, padding_ratio=0.08):
    """
    Create a round launcher icon (ic_launcher_round) with a circular mask.
    """
    sq = make_square_icon(src_img, size, padding_ratio)
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, size - 1, size - 1), fill=255)
    
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(sq, (0, 0), mask)
    return out


# Android density -> pixel size
SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def main():
    res_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("android/app/src/main/res")
    
    if not res_dir.exists():
        print(f"Directory {res_dir} does not exist. Creating...")
        res_dir.mkdir(parents=True, exist_ok=True)
        
    logo = get_logo_image()
    
    for folder_name, size in SIZES.items():
        folder = res_dir / folder_name
        folder.mkdir(parents=True, exist_ok=True)
        
        # Save standard square icon
        sq_img = make_square_icon(logo, size)
        sq_img.save(folder / "ic_launcher.png", "PNG")
        
        # Save round icon
        rd_img = make_round_icon(logo, size)
        rd_img.save(folder / "ic_launcher_round.png", "PNG")
        
        print(f"Generated icons for {folder_name} ({size}x{size}px)")


if __name__ == "__main__":
    main()
