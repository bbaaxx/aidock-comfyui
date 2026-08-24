# aidock-comfyui (revived + hardened fork)

Run [ComfyUI](https://github.com/Comfy-Org/ComfyUI) as a secure, self-provisioning [Runpod](https://runpod.io) pod. Fork of the unmaintained [ai-dock/comfyui](https://github.com/ai-dock/comfyui), rebuilt on current ComfyUI and hardened for single-tenant cloud use (see [Security & Privacy](#security--privacy)).

- **Images:** `ghcr.io/bbaaxx/aidock-comfyui`
- **Services:** ComfyUI, API wrapper, service portal, Jupyter (opt-in), Syncthing (opt-in), SSH
- **Auth:** all web services behind login; SSH pubkey-only

---

## Quick start (Runpod)

1. **Console → Pods → Deploy** → pick a GPU host → choose template `aidock-comfyui-revived`.
2. Wait for boot: image pull → provisioning (downloads models) → services up.
3. Open **https://\<pod-id\>-1111.proxy.runpod.net** (portal) or **-8188** (ComfyUI) and log in.

Template ships with:

| Setting | Value |
| --- | --- |
| Image | `ghcr.io/bbaaxx/aidock-comfyui:v2-cuda-12.4.1-base-22.04-cu128-v0.33.1` |
| Ports | `8188/http` ComfyUI, `1111/http` portal, `8888/http` Jupyter, `22/tcp` SSH |
| Env | `WORKSPACE=/workspace`, `PROVISIONING_SCRIPT` (custom.sh), `CF_QUICK_TUNNELS=false`, `SUPERVISOR_NO_AUTOSTART=jupyter,syncthing`, secrets via `{{ RUNPOD_SECRET_* }}` |

**Attach a volume (recommended).** With `WORKSPACE=/workspace` set and a volume mounted there, ComfyUI itself plus all models/outputs live on the volume: provisioning is skipped on restart/redeploy and container disk stays nearly empty. Size guide: ComfyUI ~2GB + your models (SDXL-class ≈7GB each) — 50GB is a comfortable start; container disk 20-30GB holds the image + torch venvs.

## Image tags & host driver compatibility

**Pick by the host's NVIDIA driver version** (shown in console host details; community hosts vary):

| Tag | torch | ComfyUI | Min driver |
| --- | --- | --- | --- |
| `:v2-cuda-12.4.1-base-22.04-cu128-v0.33.1` ← template default | 2.11.0+cu128 | v0.33.1 | 570.86 (most community hosts) |
| `:latest-cuda` / `:-cu130-v0.33.1` | 2.13.0+cu130 | v0.33.1 | 580.65 |
| `:v2-cuda-12.1.1-base-22.04-v0.26.2` | 2.5.1+cu121 | v0.26.2 | 530 (legacy fallback) |
| `:v2-cpu-22.04-v0.26.2` | 2.5.1+cpu | v0.26.2 | — |

Wrong tier symptom: `torch.cuda.is_available() == False` / "driver too old" → redeploy on a newer-driver host or use a lower tier.

## Access & credentials

| What | Where | Auth |
| --- | --- | --- |
| Service portal | `https://<pod-id>-1111.proxy.runpod.net` | `WEB_USER` / `WEB_PASSWORD` |
| ComfyUI | `https://<pod-id>-8188.proxy.runpod.net` | same |
| API wrapper | `https://<pod-id>-8188.proxy.runpod.net/ai-dock/api/` (+`/docs`) | same |
| Jupyter | `https://<pod-id>-8888.proxy.runpod.net` (when enabled) | same |
| SSH | `ssh -i ~/.runpod/ssh/RunPod-Key-Go root@<pod_ip> -p <port>` | pubkey only |

Get SSH details anytime:

```bash
runpodctl ssh info <pod-id>     # prints ready-to-use ssh command
```

Credentials come from Runpod secrets (`Console → Settings → Secrets`) referenced in template env as `{{ RUNPOD_SECRET_<name> }}` — never stored in plaintext.

## Provisioning (models & nodes at boot)

The template runs [`config/provisioning/custom.sh`](config/provisioning/custom.sh) at first boot. Edit the CONFIG section (or fork and point `PROVISIONING_SCRIPT` at your own URL):

```bash
NODES=(
    # custom nodes, pinned: "url@commit-sha"
    "https://github.com/ltdrdata/ComfyUI-Manager@4f56cf3d..."
)
CHECKPOINT_MODELS=(
    # "url|filename|sha256"  (filename, sha256 optional)
    "https://huggingface.co/.../model.safetensors|model.safetensors"
)
# also: UNET_MODELS (FLUX), CLIP_MODELS, VAE_MODELS, LORA_MODELS,
#       CONTROLNET_MODELS, ESRGAN_MODELS (upscalers), EMBEDDINGS,
#       PIP_PACKAGES, APT_PACKAGES
```

Behavior:

- **Idempotent** — existing files are skipped; re-provisioning a pod with a persistent disk downloads nothing.
- Files land in the correct ComfyUI model dirs automatically (checkpoints vs FLUX unets vs loras etc.).
- `HF_TOKEN` / `CIVITAI_TOKEN` (from secrets) are applied automatically for gated downloads.
- Optional `|sha256` verifies integrity; mismatch deletes the file and fails provisioning.
- Downloads use multi-connection aria2 (~150x faster than wget on throttled hosts).

Logs: `/var/log/provisioning.log` on the pod.

### Private post-provisioning hook

For private model URLs or extra setup that should NOT live in the public repo:

1. Write your script locally (it runs after models land, before services restart; don't restart services in it — handled for you).
2. Store it base64-encoded as a Runpod secret, e.g. `CustomProv`:
   ```bash
   base64 -i myscript.sh | tr -d '\n'   # paste output as the secret value
   ```
3. Template env: `CUSTOM_PROVISION_B64={{ RUNPOD_SECRET_CustomProv }}`

The provisioning engine decodes and runs it at the end of every boot. To change what runs, edit the secret value — no repo changes, nothing public.

### Pushing local files (faces, custom assets)

`pod-push.sh <pod-id> <local_dir/> <pod_path/>` (SSH, perms auto-fixed) — e.g. the reactor faces folder. Get pod-id from `runpodctl pod list`.

## Custom nodes & ComfyUI-Manager security

Manager ships at `security_level=strong` (remote node/pip installs blocked) with telemetry off. To install nodes via the Manager UI, relax **temporarily**:

```bash
# live, over SSH:
manager-security weak --restart
# ...install nodes...
manager-security strong --restart
```

or at deploy time: env `COMFYUI_MANAGER_SECURITY_LEVEL=weak` (valid: `strong|middle|normal|weak`).

Deliberately **not** changeable from any web UI: lowering defenses must require operator shell/deploy access, not just a web session.

Nodes listed in `NODES` (provisioning script) are cloned at pinned commits — no floating-HEAD supply chain.

## Optional services

| Service | Enable |
| --- | --- |
| Jupyter | `supervisorctl start jupyter` over SSH, or drop `jupyter` from `SUPERVISOR_NO_AUTOSTART` at deploy |
| Syncthing | same, via `supervisorctl start syncthing`; hardened to direct connections only (no relays/discovery) — expose `22999/tcp` and add the device manually as `tcp://<pod_ip>:<mapped_port>` |

## File sync (recommended: SSH transport)

Reuses the pubkey-only SSH endpoint; adds no listening services and no third-party infrastructure:

```bash
# one-shot (outputs, models)
# NOTE: macOS files often carry owner-only perms (uid 501, mode 700) and
# stock macOS rsync (2.6.9) has unreliable --chmod. After pushing files to
# the pod, normalize perms there (comfyui runs as non-root "user"):
#   ssh ... 'chmod -R u+rwX,go+rX /workspace/ComfyUI/models/<dir>'
# (or install modern rsync via brew, where --chmod=Fu+rw,Fgo+r works)
rsync -avz -e "ssh -i ~/.runpod/ssh/RunPod-Key-Go -p <pod_ssh_port>" \
  root@<pod_ip>:/opt/ComfyUI/output/ ./outputs/

# continuous two-way (https://mutagen.io)
mutagen sync create --name=pod ./workspace \
  "root@<pod_ip>:<pod_ssh_port>:/workspace" -i "~/.runpod/ssh/RunPod-Key-Go"
```

## Environment variables (fork-relevant)

| Variable | Default | Notes |
| --- | --- | --- |
| `WEB_USER` / `WEB_PASSWORD` | — (no default!) | web auth; use `{{ RUNPOD_SECRET_* }}` |
| `WEB_ENABLE_AUTH` | `true` | never set false on a public pod |
| `PROVISIONING_SCRIPT` | custom.sh URL | script sourced at boot |
| `HF_TOKEN` / `CIVITAI_TOKEN` | — | gated downloads; use secrets |
| `SUPERVISOR_NO_AUTOSTART` | `jupyter,syncthing` | comma-separated services to keep off |
| `COMFYUI_MANAGER_SECURITY_LEVEL` | `strong` | see above; revert to strong after use |
| `CF_QUICK_TUNNELS` | `false` | public trycloudflare URLs — keep off |
| `COMFYUI_ARGS` | — | extra ComfyUI CLI flags (operator-trusted) |
| `AUTO_UPDATE` | `false` | keep false (pulls unsigned code at boot) |

Base-image variables (ports, SSH keys, tunnels): [ai-dock wiki](https://github.com/ai-dock/base-image/wiki/2.0-Environment-Variables).

## Security & privacy

This fork hardens the ai-dock defaults (full audit + threat model in the project wiki):

- No default credentials anywhere; all web traffic gated by caddy auth (`Secure`, `HttpOnly` cookies)
- SSH pubkey-only (`PasswordAuthentication no`)
- API wrapper: SSRF guard on workflow URL fetching, path-traversal protection on outputs
- Storage symlink daemon refuses planted-symlink escapes
- Supervisor control panel bound to loopback (upstream exposes it unauthenticated on `0.0.0.0:9001`)
- Supply chain: pinned node commits, pinned Python deps, optional model checksums, `AUTO_UPDATE` off
- Privacy: no telemetry (Manager `share_option=none`), no cloud tunnels, Syncthing direct-only when enabled, prompts/tokens stay out of logs

## Building

GitHub Actions → **Docker Build** → Run workflow (manual dispatch). Matrix builds all tiers (cu121/cu128/cu130/cpu) and pushes to ghcr.io. A registry-side `unknown blob` push flake occasionally fails one job — **Re-run failed jobs** resolves it.

---

_Upstream credit: [ai-dock/comfyui](https://github.com/ai-dock/comfyui) by [@robballantyne](https://github.com/robballantyne)._
