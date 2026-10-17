import numpy as np
from PIL import Image
from collections import deque
U='/root/.claude/uploads/f53586ee-2bba-539c-87ee-84901b62717f/'

def sample(path, s, ox, oy, inner=0.5):
    im=np.asarray(Image.open(path).convert('RGBA')).astype(float)
    H,W,_=im.shape
    nx=int((W-ox)//s); ny=int((H-oy)//s)
    out=np.zeros((ny,nx,4))
    for j in range(ny):
        for i in range(nx):
            x0=ox+i*s; y0=oy+j*s
            a=int(x0+s*(1-inner)/2); b=max(a+1,int(x0+s*(1+inner)/2))
            c=int(y0+s*(1-inner)/2); d=max(c+1,int(y0+s*(1+inner)/2))
            blk=im[c:d,a:b].reshape(-1,4)
            out[j,i]=np.median(blk,axis=0)
    return out

def remove_bg(px, tol=40, bg=None):
    H,W,_=px.shape
    rgb=px[:,:,:3]
    if bg is None:
        corners=[rgb[0,0],rgb[0,-1],rgb[-1,0],rgb[-1,-1]]
        bg=np.median(np.array(corners),axis=0)
    near=(np.abs(rgb-bg).max(axis=2)<tol) | (px[:,:,3]<128)
    seen=np.zeros((H,W),bool); q=deque()
    for x in range(W):
        for y in (0,H-1):
            if near[y,x] and not seen[y,x]: seen[y,x]=True; q.append((y,x))
    for y in range(H):
        for x in (0,W-1):
            if near[y,x] and not seen[y,x]: seen[y,x]=True; q.append((y,x))
    while q:
        y,x=q.popleft()
        for dy,dx in ((1,0),(-1,0),(0,1),(0,-1)):
            yy,xx=y+dy,x+dx
            if 0<=yy<H and 0<=xx<W and near[yy,xx] and not seen[yy,xx]:
                seen[yy,xx]=True; q.append((yy,xx))
    out=px.copy(); out[:,:,3]=np.where(seen,0,255)
    return out

def crop(px):
    a=px[:,:,3]>0
    ys,xs=np.where(a)
    return px[ys.min():ys.max()+1, xs.min():xs.max()+1]

def quantize(px, k):
    from PIL import Image as I
    rgb=px[:,:,:3].astype(np.uint8); a=px[:,:,3]
    im=I.fromarray(rgb).quantize(colors=k, method=I.Quantize.MEDIANCUT).convert('RGB')
    q=np.asarray(im).astype(float)
    out=np.dstack([q,a]); return out

def to_img(px):
    return Image.fromarray(np.clip(px,0,255).astype(np.uint8),'RGBA')

def components(px):
    a=px[:,:,3]>0; H,W=a.shape; lab=np.zeros((H,W),int); n=0
    for y in range(H):
        for x in range(W):
            if a[y,x] and not lab[y,x]:
                n+=1; q=deque([(y,x)]); lab[y,x]=n
                while q:
                    cy,cx=q.popleft()
                    for dy in (-1,0,1):
                        for dx in (-1,0,1):
                            yy,xx=cy+dy,cx+dx
                            if 0<=yy<H and 0<=xx<W and a[yy,xx] and not lab[yy,xx]:
                                lab[yy,xx]=n; q.append((yy,xx))
    return lab,n

def shrink(px, maxw, maxh):
    """Fit pixel art in a box: area-average then snap each pixel to the nearest original colour."""
    H,W,_=px.shape
    f=max(W/maxw, H/maxh)
    if f<=1: return px
    nw,nh=int(round(W/f)),int(round(H/f))
    img=to_img(px)
    # premultiplied average
    arr=px.copy(); arr[:,:,:3]*=arr[:,:,3:4]/255
    small=np.asarray(Image.fromarray(np.clip(arr,0,255).astype(np.uint8),'RGBA').resize((nw,nh),Image.BOX)).astype(float)
    al=small[:,:,3]
    rgb=np.where(al[:,:,None]>0, small[:,:,:3]*255/np.maximum(al[:,:,None],1),0)
    pal=np.unique(px[px[:,:,3]>0][:,:3].astype(int),axis=0).astype(float)
    flat=rgb.reshape(-1,3)
    d=((flat[:,None,:]-pal[None,:,:])**2).sum(axis=2)
    snapped=pal[d.argmin(axis=1)].reshape(nh,nw,3)
    out=np.dstack([snapped, np.where(al>110,255,0)])
    return out

# ---------------------------------------------------------------------------
#  HOW THE 2026-10-17 CONTROLLER PICTURES WERE MADE (Steven's own finds,
#  kept in docs/art/sources/, which never ships). Each source is pixel art
#  blown up N times; sample() reads one colour per real pixel, remove_bg()
#  clears the background from the edges inwards, crop() trims.
#    wii-remote-and-gamepad.png  s=5    split into wiiremote + gamepad
#    xbox-one.png  s=5.04 (4,0)   xbox-og.png  s=5.04 (5,4)   pad-dark.png  s=7
#    xbox-series.png  s=4, then halved   ps4-black.png  s=10
#    ps4-grey.png  s=5.56 (0,5)   ps5.png  s=5.9 (3,2)   mouse-white.png  s=7.72 (4,4)
#    stock-wave-mouse.webp  s=5.82 (1.5,0.5), two colours -> cm-mouse.png
#    stock-pad.webp  s=5.22 (2,2), recoloured black, the mouse's waves on top
#                    -> cm-pad.png; both on a 40 px light square
#  U at the top is where the sources were read from; point it at sources/.
# ---------------------------------------------------------------------------
