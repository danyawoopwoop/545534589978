#!/usr/bin/env bash
set -euo pipefail

export WORKSPACE="/workspace"
export COMFY_DIR="$WORKSPACE/ComfyUI"
export PY="/venv/main/bin/python"
export PIP="/venv/main/bin/pip"

# ========================================================
# КОММЕНТАРИЙ: Токен Civitai (уже внесен)
# ========================================================
CIVITAI_TOKEN="66e58af72a977c3270b4f2c5877da4b3"
# ========================================================

echo "[IntoRealism Workflow] provisioning start"

if [ -f /venv/main/bin/activate ]; then
  . /venv/main/bin/activate
fi

# Установка системных зависимостей
apt-get update -y || true
apt-get install -y git wget curl rsync ca-certificates libgl1-mesa-glx libglib2.0-0 || true
apt-get clean && rm -rf /var/lib/apt/lists/*

mkdir -p "$WORKSPACE"

# ------------------------------------------------
# Install ComfyUI
# ------------------------------------------------

if [ ! -d "$COMFY_DIR" ]; then
  git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFY_DIR"
else
  git -C "$COMFY_DIR" pull || true
fi

# ------------------------------------------------
# Python deps
# ------------------------------------------------

"$PIP" install -U pip setuptools wheel

"$PIP" install \
ultralytics \
opencv-python \
onnxruntime \
segment-anything \
accelerate \
matplotlib \
GitPython

"$PIP" install -r "$COMFY_DIR/requirements.txt"

# ------------------------------------------------
# Custom Nodes
# ------------------------------------------------

cd "$COMFY_DIR/custom_nodes"

[ -d "ComfyUI-Manager" ] || git clone https://github.com/Comfy-Org/ComfyUI-Manager.git
[ -d "ComfyUI-Impact-Pack" ] || git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git
[ -d "ComfyUI-Impact-Subpack" ] || git clone https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git
[ -d "rgthree-comfy" ] || git clone https://github.com/rgthree/rgthree-comfy.git

# ------------------------------------------------
# Model folders
# ------------------------------------------------

mkdir -p \
"$COMFY_DIR/models/checkpoints" \
"$COMFY_DIR/models/vae" \
"$COMFY_DIR/models/loras" \
"$COMFY_DIR/models/sams" \
"$COMFY_DIR/models/ultralytics/bbox"

# ------------------------------------------------
# Download base models
# ------------------------------------------------

cd "$COMFY_DIR/models"

# checkpoint - ИСПРАВЛЕНО: Добавлены флаги для устранения ошибки 400
wget -nc -P checkpoints \
--header="Authorization: Bearer $CIVITAI_TOKEN" \
--auth-no-challenge \
--trust-server-names \
"https://civitai.com/api/download/models/2472650" \
-O checkpoints/lustifySDXLNSFW_ggwpV7.safetensors

# VAE
wget -nc -P vae \
"https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors"

# SAM
wget -nc -P sams \
"https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth"

# Ultralytics detector
wget -nc -P ultralytics/bbox \
"https://huggingface.co/bingsu/adetailer/resolve/main/Eyeful_v2-Paired.pt"

# ------------------------------------------------
# LORA DOWNLOAD SECTION
# ------------------------------------------------

LORAS=(
"https://huggingface.co/danya712/24121412/resolve/main/0MY12RWXE4VY3KXZAN6H9N2D70.safetensors?download=true|eveline_lora_sdxl.safetensors"
"https://civitai.com/api/download/models/1627770?type=Model&format=SafeTensor|leaked_nudes.safetensors"
"https://civitai.com/api/download/models/871108?type=Model&format=SafeTensor|pussy_v5.safetensors"
)

echo "[Downloading LoRAs]"

for item in "${LORAS[@]}"; do
    URL=$(echo $item | cut -d "|" -f1)
    NAME=$(echo $item | cut -d "|" -f2)
    DEST="$COMFY_DIR/models/loras/$NAME"

    if [ -f "$DEST" ]; then
        echo "[SKIP] $NAME already exists"
    else
        echo "[DL] $NAME"
        if [[ $URL == *"civitai.com"* ]]; then
            # ИСПРАВЛЕНО: Добавлены флаги для LoRA с Civitai
            wget -q --show-progress --header="Authorization: Bearer $CIVITAI_TOKEN" \
            --auth-no-challenge --trust-server-names "$URL" -O "$DEST"
        else
            wget -q --show-progress "$URL" -O "$DEST"
        fi
    fi
done

# ------------------------------------------------
# Start ComfyUI
# ------------------------------------------------

pkill -f "ComfyUI/main.py" || true
sleep 1

nohup "$PY" "$COMFY_DIR/main.py" \
--listen 0.0.0.0 \
--port 8188 \
> /workspace/comfyui.log 2>&1 &

echo "================================="
echo "ComfyUI started"
echo "LOG: tail -n 200 /workspace/comfyui.log"
echo "================================="
