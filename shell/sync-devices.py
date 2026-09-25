#!/usr/bin/env python3
"""
同步官方最新設備資料庫並自動注入更新 GitHub Actions Workflow 選單
"""
import json
import re
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DEVICES_JSON_PATH = BASE_DIR / "data" / "devices.json"
WORKFLOW_PATH = BASE_DIR / ".github" / "workflows" / "build-firmware.yml"

def load_local_devices():
    if DEVICES_JSON_PATH.exists():
        with open(DEVICES_JSON_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}

def fetch_upstream_devices():
    """從官方韌體選擇器資料庫獲取最新支援清單"""
    urls = [
        "https://downloads.immortalwrt.org/releases/24.10.0/.overview.json",
        "https://downloads.openwrt.org/releases/24.10.0/.overview.json"
    ]
    found_profiles = {}
    for url in urls:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                for item in data.get("profiles", []):
                    pid = item.get("id")
                    target = item.get("target")
                    titles = item.get("titles", [])
                    title_str = titles[0].get("title", pid) if titles else pid
                    vendor_str = titles[0].get("vendor", "") if titles else ""
                    if pid and target:
                        found_profiles[pid] = {
                            "vendor": vendor_str,
                            "title": title_str,
                            "target": target
                        }
        except Exception as e:
            print(f"嘗試抓取 {url} 略過: {e}")
    return found_profiles

def main():
    print("正在讀取本地設備庫...")
    devices = load_local_devices()
    print(f"本地現有設備數: {len(devices)}")

    upstream = fetch_upstream_devices()
    print(f"官方遠端資料庫掃描完成，發現 {len(upstream)} 款設備規格。")

    # 針對知名主流設備自動校對或擴增
    for pid, info in upstream.items():
        # 如果是新加入的熱門品牌路由器，自動補充其資訊
        vendor_lower = info["vendor"].lower()
        if any(brand in vendor_lower for brand in ["xiaomi", "redmi", "gl.inet", "friendlyarm", "raspberry", "asus"]):
            slug = pid.replace("-", "_").lower()
            if slug not in devices:
                devices[slug] = {
                    "name": f"[{info['vendor']}] {info['title']}",
                    "target": info["target"],
                    "profile": pid
                }

    # 寫回 data/devices.json
    DEVICES_JSON_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(DEVICES_JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(devices, f, ensure_ascii=False, indent=2)
    print("✓ data/devices.json 已更新完成。")

    # 動態產生 workflow 下拉選單 YAML 內容
    yaml_options = []
    for key, data in devices.items():
        yaml_options.append(f"          - '{key}: {data['name']}'")
    options_str = "\n".join(yaml_options)

    # 改寫 build-firmware.yml 的 options 區塊
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    pattern = r"(# --- AUTO_DEVICES_START ---)(.*?)(# --- AUTO_DEVICES_END ---)"
    replacement = f"\\1\n{options_str}\n          \\3"
    new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

    with open(WORKFLOW_PATH, "w", encoding="utf-8") as f:
        f.write(new_content)

    print("✓ .github/workflows/build-firmware.yml 下拉選單已自動重構更新完成！")

if __name__ == "__main__":
    main()
