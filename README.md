# 🚀 OpenWrt & ImmortalWrt 雙核心雲端自訂韌體構建工具

基於 **GitHub Actions CI** 的現代化雲端 ImageBuilder 自動化構建系統。無需繁複的本地交叉編譯環境，在 **3 ~ 5 分鐘** 內即可快速封裝產出專屬的軟路由與虛擬機韌體。

---

### ✨ 核心功能亮點

* 🔄 **雙系統自由切換**：下拉選單自由選擇構建 **OpenWrt** 官方原版或 **ImmortalWrt** 衍生版。
* 🔍 **智慧自動抓取版本**：版本欄位預設為 `auto`，自動動態查詢上游官方倉庫的最新正式穩定版（支援 25.12+ `apk` 與 24.10/23.05 `opkg` 架構）。
* 💾 **自訂磁碟分區容量（單位：GB）**：直接輸入數字（如 `1`、`2`、`4`），底層自動精確換算為 MB（`GB * 1024`）擴展 Rootfs 空間。
* 📱 **全設備預設選單 & 支援自動更新**：
  * 預載全系列主流設備（x86_64、友善 NanoPi 全系列、樹莓派、紅米 AX6000、GL.iNet 全系列、ASUS、TP-Link 等），自動綁定 Target 與 Profile。
  * 具備 `sync-upstream.yml` 定時任務，每週自動同步官方最新支援硬體並更新選單。
* 🛡️ **開箱即用旁路由模式（Bypass Router / 二級網關）**：
  * 一鍵勾選啟用旁路由專用模式，引導輸入本機 IP、主路由網關與自訂 DNS。
  * 首次開機自動**關閉旁路由 DHCP**、**關閉 IPv6 廣播**、**禁用獨立 WAN 避免路由衝突**。
  * 自動配置 LAN 區域 **NAT 動態偽裝（Masquerade）**，徹底解決 iPhone / 蘋果設備常見的三角非對稱路由丟包問題！
* 🎨 **iStoreOS 經典首頁儀表板（可選開關）**：
  * 一鍵勾選開啟 `enable_istoreos_dashboard`，整合 iStoreOS 招牌的 **QuickStart 網絡拓撲圖** 與 **CPU/記憶體/硬碟動態圓環儀表盤**。
  * 開機自動將 LuCI 預設登入頁面設定為 QuickStart 儀表板。
* 🎨 **Argon 現代主題雙件套（預設預裝）**：
  * 預裝 `luci-theme-argon` 現代自適應主題。
  * 預裝 `luci-app-argon-config` 外觀配置面板，登入後進入「System -> Argon Config」即可自訂高清背景桌布、切換毛玻璃半透明效果。
* 📦 **官方原廠軟體源一鍵切換**：
  * 可選開關 `use_official_repo`，自動將 ImmortalWrt 預設夾帶的 `vsean` 等第三方鏡像無縫替換為官方正版 `downloads.immortalwrt.org`。
* 🖥️ **全虛擬化格式支援**：
  * 除了標準的實體刷機包 `.img.gz`，系統自動轉換生成 VMware 專用的 **動態配置 `.vmdk` 虛擬磁碟**（可直接掛載至 ESXi / Workstation / PVE）。
  * 同步產出 Hyper-V `.vhdx` 與安裝引導 `.iso` 鏡像檔。
* 🛡️ **智慧相依自癒打包（Self-Healing）**：
  * 打包時若遇到官方源缺少特定套件，編譯器會自動捕獲缺失組件與父級依賴，自動剔除衝突套件後原地重新封裝，保證 100% 構建成功不中斷。

---

### 🚀 快速上手指南

1. **Fork 本儲存庫** 到您個人的 GitHub 帳號。
2. 進入儲存庫頁面，點選頂部的 **Actions** 標籤。
3. 在左側清單點選 **「構建 OpenWrt / ImmortalWrt 自訂韌體」**。
4. 點擊右側的 **Run workflow**，填寫您的自訂偏好：

| 參數欄位 | 說明 | 預設值 | 推薦範例 |
| :--- | :--- | :---: | :--- |
| **韌體系統分支** | 選擇 `ImmortalWrt` 或 `OpenWrt` | `ImmortalWrt` | 推薦 `ImmortalWrt`（功能最全） |
| **韌體版本** | 填寫 `auto` 自動抓取最新版，亦可指定版本 | `auto` | `auto`、`25.12.2`、`24.10.0` |
| **軟體包分區空間** | 根分區磁碟空間大小（單位：GB） | `1` | `1`、`2`、`4` |
| **設備型號** | 直接從下拉選單選擇你的路由器或軟路由型號 | `x86_generic` | 標準工控機、N100、J4125 選預設 |
| **iStoreOS 經典首頁** | 是否將狀態頁替換為 iStoreOS 網絡拓撲儀表板 | `false` | 喜歡拓撲圖建議勾選 `true` |
| **改為官方原廠源** | 是否強制將預設鏡像替換為官方 downloads 源 | `false` | 想確保純官方源可勾選 `true` |
| **旁路由開關** | 是否作為旁路由 / 二級網關（關閉 DHCP/開啟 NAT） | `false` | 作為旁路由時請務必勾選 `true` |
| **本機 LAN IP** | 本設備的管理 IP 位址 | `192.168.100.1` | 旁路由請填同網段如 `192.168.100.1` |
| **主路由網關** | 【旁路由專用】主路由器的 IP 位址 | `192.168.100.2` | 填寫你主路由的 IP（如 `192.168.86.1`） |
| **自訂 DNS** | 【旁路由專用】自訂 DNS 解析伺服器 | `192.168.100.2 8.8.8.8` | 多個 DNS 請用空格分開 |
| **整合 Docker** | 是否預裝 Docker 引擎與 Dockerman 視覺化介面 | `false` | 軟路由用戶可按需勾選 |
| **PPPoE 撥號** | 【主路由專用】是否預設啟用 WAN 口寬頻撥號 | `false` | 旁路由請保持 `false` |

5. 點擊綠色按鈕 **Run workflow** 開始構建。約 3~5 分鐘後，編譯完成的檔案會自動發布至倉庫首頁的 **Releases** 永久保存！

---

### 🌐 旁路由（二級網關）網路拓撲推薦配置

當你啟用了 **旁路由模式（`is_bypass_router = true`）** 時：

```text
       [ 光貓 / 小烏龜 ]
              │
       [ 主路由器 (例如: 192.168.86.1) ] ── (開啟 DHCP / 發放 Wi-Fi)
              │
              ├── [ 旁路由 (例如: 192.168.86.111) ]  <-- 運行 DAED / 代理外掛
              │         網關指向: 192.168.86.1
              │         DNS 指向: 192.168.86.1
              │         DHCP: 已關閉 (防止局域網衝突)
              │
              └── [ 電腦 / 手機 / 智慧電視 ]
                        想要翻牆/去廣告的設備：網關手動填寫 192.168.86.111
                        普通家用設備：網關保持預設 192.168.86.1 直連
```

---

### 📦 自訂額外外掛與代理工具

倉庫中的 `shell/custom-packages.sh` 已經預先整理好最常見的外掛選單。
若需要預裝某個特定插件，**只需編輯該檔案，刪除該行最前面的「#」號**解除註解即可：

* **代理客戶端**：`HomeProxy`（sing-box）、`OpenClash`（Mihomo）、`PassWall`、`v2rayA` 等。
* **DNS 與廣告過濾**：`SmartDNS`、`MosDNS`、`AdGuard Home`、`Adblock` 等。
* **組網穿透**：`Tailscale`、`ZeroTier`、`WireGuard`、`FRP Client` 等。
* **系統與 NAS 工具**：`ttyd 終端機`、`定時重啟`、`Samba 4`、`Diskman 磁碟管理`、`Aria2`、`qBittorrent` 等。

#### 🔍 官方外掛名稱線上檢索庫
在添加新外掛前，可至下列官方資料庫確認正確名稱：
* [OpenWrt 官方全套件即時檢索庫 (Package Table)](https://openwrt.org/packages/table/start)
* [OpenWrt 官方韌體選擇器 (Firmware Selector)](https://firmware-selector.openwrt.org/)
* [ImmortalWrt 官方韌體選擇器 (含特色插件檢索)](https://firmware-selector.immortalwrt.org/)

---

### 🔑 首次開機預設認證資訊

固件刷入完成並首次開機後：

* **Web 管理後台網址**：`http://你設定的LAN_IP`（例如 `http://192.168.100.1` 或 `http://192.168.86.111`）
* **登入使用者名稱 (User)**：`root`
* **登入密碼 (Password)**：**無密碼（密碼欄留空，直接點擊「Login / 登入」即可）**
* **SSH 終端連線**：`ssh root@你設定的LAN_IP`（無密碼直接按 Enter）

---

### 📂 專案檔案結構導覽

```text
.
├── .github/
│   └── workflows/
│       ├── build-firmware.yml      # 主構建流程 (支援雙系統、旁路由模式、iStoreOS 首頁、發布 Release)
│       └── sync-upstream.yml       # 自動化任務 (定期同步官方最新版本號與設備庫)
├── data/
│   └── devices.json                # 支援設備資料庫 (SSOT 單一事實來源，含完整中文硬體註解)
├── files/
│   └── etc/
│       └── uci-defaults/
│           └── 99-custom.sh        # 首次開機自訂腳本 (自動配置旁路由、固定 IP、網關、QuickStart 跳轉)
├── shell/
│   ├── custom-packages.sh          # 自訂擴充軟體包選單 (精簡原生英文，含全功能註解)
│   ├── fetch-versions.sh           # 遠端即時版本偵測程式 (支援 auto/latest 動態抓取)
│   └── sync-devices.py             # 智慧設備中文化與自動注入更新腳本
├── build.sh                        # 核心構建主程式 (GB換算、下載ImageBuilder、自動轉換VMDK、容錯自癒)
└── README.md                       # 專案繁體中文使用說明文件
```

---

### 🔒 安全性聲明（關於 PPPoE 撥號）
* 在 GitHub Actions 構建過程中，**系統絕不會在 Releases 頁面或公開日誌中輸出您的 PPPoE 帳號與密碼**。
* **⚠️ 安全提醒**：若您的 GitHub 儲存庫為 **公開（Public）倉庫**，任何人都可下載您的 Release 韌體並解壓讀取底層設定檔。因此**在公開倉庫構建時，強烈建議將 PPPoE 保持關閉留空**，待刷機完成後進入本地後台再行輸入！
