#!/usr/bin/env python3
"""
同步官方最新設備資料庫並自動注入中文化與設備註解，改寫 build-firmware.yml 選單
"""
import json
import re
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DEVICES_JSON_PATH = BASE_DIR / "data" / "devices.json"
WORKFLOW_PATH = BASE_DIR / ".github" / "workflows" / "build-firmware.yml"

# 1. 品牌英文 -> 繁體中文對照字典
VENDOR_ZH_MAP = {
    "x86": "x86",
    "FriendlyElec": "友善 NanoPi",
    "FriendlyARM": "友善 NanoPi",
    "Raspberry Pi": "樹莓派",
    "Xiaomi": "小米",
    "Redmi": "紅米",
    "GL.iNet": "GL.iNet",
    "ASUS": "華碩 ASUS",
    "TP-Link": "TP-Link",
    "Qihoo": "360",
    "360": "360",
    "JCG": "捷稀 JCG",
    "Phicomm": "斐訊",
    "H3C": "華三 H3C",
    "Bananapi": "香蕉派 Banana Pi",
    "Sinovoip": "香蕉派 Banana Pi",
    "Linksys": "領勢 Linksys",
    "Netgear": "網件 Netgear",
    "Mercusys": "水星",
    "ZTE": "中興 ZTE",
}

# 2. 熱門知名設備之精準中文詳細備註
KNOWN_DESCRIPTIONS = {
    "x86_generic": "[x86] 標準軟路由 / 工控機 (N100, J4125) / 虛擬機 (PVE, ESXi, PC)",
    "x86_legacy": "[x86] 傳統 BIOS 引導舊主機 (Legacy MBR)",
    "friendlyarm_nanopi-r2s": "[友善] NanoPi R2S (雙千兆經典軟路由)",
    "friendlyarm_nanopi-r2c": "[友善] NanoPi R2C (雙千兆軟路由)",
    "friendlyarm_nanopi-r4s": "[友善] NanoPi R4S (RK3399 高效軟路由)",
    "friendlyarm_nanopi-r4se": "[友善] NanoPi R4SE (內建 eMMC 高效軟路由)",
    "friendlyarm_nanopi-r5s": "[友善] NanoPi R5S (三網口 雙 2.5G 軟路由)",
    "friendlyarm_nanopi-r5c": "[友善] NanoPi R5C (雙 2.5G 迷你軟路由)",
    "friendlyarm_nanopi-r6s": "[友善] NanoPi R6S (RK3588 雙 2.5G 旗艦軟路由)",
    "friendlyarm_nanopi-r6c": "[友善] NanoPi R6C (RK3588 旗艦軟路由)",
    "rpi-4": "[樹莓派] Raspberry Pi 4 Model B / CM4",
    "rpi-5": "[樹莓派] Raspberry Pi 5 (新一代高效單板電腦)",
    "rpi-3": "[樹莓派] Raspberry Pi 3 Model B / B+",
    "xiaomi_redmi-router-ax6000": "[紅米] Redmi AX6000 (MT7986 旗艦家用路由)",
    "xiaomi_mi-router-ax3000t": "[小米] 小米路由器 AX3000T (高 CP 值 Wi-Fi 6)",
    "xiaomi_mi-router-wr30u": "[小米] 小米路由器 WR30U (一般版 / 電信運營商版)",
    "xiaomi_redmi-router-ax3200": "[紅米] Redmi AX3200 / 小米 AX6S",
    "xiaomi_mi-router-4a-gigabit": "[小米] 小米路由器 4A 千兆版 (MT7621)",
    "glinet_gl-mt3000": "[GL.iNet] GL-MT3000 (Beryl AX 便攜旅行路由)",
    "glinet_gl-mt6000": "[GL.iNet] GL-MT6000 (Flint 2 雙 2.5G 旗艦路由)",
    "glinet_gl-mt2500": "[GL.iNet] GL-MT2500 / MT2500A (Brume 2 雙網口網關)",
    "glinet_gl-axt1800": "[GL.iNet] GL-AXT1800 (Slate AX 三頻旅行路由)",
    "glinet_gl-ax1800": "[GL.iNet] GL-AX1800 (Flint 雙頻 Wi-Fi 6 路由)",
    "asus_tuf-gaming-ax4200": "[華碩] ASUS TUF Gaming AX4200 電競路由器",
    "tplink_tl-xdr6088": "[TP-Link] TL-XDR6088 (雙 2.5G 旗艦 Wi-Fi 6)",
    "qihoo_360-t7": "[360] 360 T7 (聯發科高性價比神機)",
    "jcg_q30-pro": "[捷稀] JCG Q30 Pro (MT7981 Wi-Fi 6)",
    "phicomm_k2p": "[斐訊] Phicomm K2P (MT7621 經典千兆神機)",
}

def format_chinese_name(pid, vendor, title, target):
    """將設備名稱與品牌轉換為優雅的中文描述格式"""
    # 1. 優先使用手動精心設定的中文解釋
    if pid in KNOWN_DESCRIPTIONS:
        return KNOWN_DESCRIPTIONS[pid]

    # 2. 自動中文化品牌名稱
    vendor_zh = VENDOR_ZH_MAP.get(vendor, vendor)
    
    # 清理標題重複包含品牌名稱的問題 (例: Xiaomi Xiaomi Router -> 路由器)
    clean_title = title
    for v in [vendor, vendor_zh]:
        clean_title = re.sub(rf"^{v}\s+", "", clean_title, flags=re.IGNORECASE)

    return f"[{vendor_zh}] {clean_title} ({target})"

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

    upstream = fetch_upstream_devices()
    print(f"掃描官方資料庫完畢，發現 {len(upstream)} 款設備規格。")

    # 自動中文化並收錄熱門品牌
    for pid, info in upstream.items():
        vendor_lower = info["vendor"].lower()
        if any(brand in vendor_lower for brand in ["xiaomi", "redmi", "gl.inet", "friendlyarm", "raspberry", "asus", "tplink", "qihoo"]):
            slug = pid.replace("-", "_").lower()
            name_zh = format_chinese_name(pid, info["vendor"], info["title"], info["target"])
            devices[slug] = {
                "name": name_zh,
                "target": info["target"],
                "profile": pid
            }

    # 確保基本 x86 條目始終存在
    if "x86_generic" not in devices:
        devices["x86_generic"] = {
            "name": KNOWN_DESCRIPTIONS["x86_generic"],
            "target": "x86/64",
            "profile": "generic"
        }
    if "x86_legacy" not in devices:
        devices["x86_legacy"] = {
            "name": KNOWN_DESCRIPTIONS["x86_legacy"],
            "target": "x86/64",
            "profile": "legacy"
        }

    # 寫入 data/devices.json
    DEVICES_JSON_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(DEVICES_JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(devices, f, ensure_ascii=False, indent=2)
    print("✓ data/devices.json 已完成全設備中文標註與更新。")

    # 自動改寫 build-firmware.yml 下拉選單
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

        print("✓ build-firmware.yml 下拉選單已注入中文註解選項！")

if __name__ == "__main__":
    main()
