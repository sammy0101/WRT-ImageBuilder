#!/usr/bin/env python3
"""
同步官方最新設備資料庫並自動維護 devices.json
"""
import os
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

    for pid, info in upstream.items():
        vendor_lower = info["vendor"].lower()
        if any(brand in vendor_lower for brand in ["xiaomi", "redmi", "gl.inet", "friendlyarm", "raspberry", "asus"]):
            slug = pid.replace("-", "_").lower()
            if slug not in devices:
                devices[slug] = {
                    "name": f"[{info['vendor']}] {info['title']}",
                    "target": info["target"],
                    "profile": pid
                }

    # 1. 寫入 data/devices.json (GitHub Actions 可直接推送)
    DEVICES_JSON_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(DEVICES_JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(devices, f, ensure_ascii=False, indent=2)
    print("✓ data/devices.json 已更新完成。")

    # 2. 判斷是否在 GitHub Actions 雲端環境 (CI=true)
    # 若在 GitHub Actions 且未提供專用權杖時，略過改寫 workflow 檔案以避免被 GitHub 拒絕推送
    if os.environ.get("GITHUB_ACTIONS") == "true" and not os.environ.get("HAS_WORKFLOW_PAT"):
        print("ℹ️ 偵測到於 GitHub Actions 環境執行：為遵守安全限制，略過改寫 build-firmware.yml。")
        print("ℹ️ devices.json 資料庫已是最新，編譯時將自動讀取最新設備。")
        return

    # 若在本地執行，同步刷新 workflow 下拉選單
    if WORKFLOW_PATH.exists():
        yaml_options = []
        for key, data in devices.items():
            yaml_options.append(f"          - '{key}: {data['name']}'")
        options_str = "\n".join(yaml_options)

        with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
            content = f.read()

        pattern = r"(# --- AUTO_DEVICES_START ---)(.*?)(# --- AUTO_DEVICES_END ---)"
        replacement = f"\\1\n{options_str}\n          \\3"
        new_content = re.sub(pattern, replacement, content, flags=re.DOTALL)

        with open(WORKFLOW_PATH, "w", encoding="utf-8") as f:
            f.write(new_content)

        print("✓ 本地 build-firmware.yml 下拉選單已自動重構完成！")

if __name__ == "__main__":
    main()
